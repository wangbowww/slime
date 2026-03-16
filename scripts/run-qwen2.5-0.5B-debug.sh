#!/bin/bash

# for debug, on single A6000 48G

# for rerun the task
pkill -9 sglang
sleep 3
ray stop --force
pkill -9 ray
pkill -9 python
sleep 3
pkill -9 ray
pkill -9 python

set -ex

# will prevent ray from buffering stdout/stderr
export PYTHONBUFFERED=16
NVLINK_COUNT=$(nvidia-smi topo -m 2>/dev/null | grep -o 'NV[0-9][0-9]*' | wc -l)
if [ "$NVLINK_COUNT" -gt 0 ]; then
    HAS_NVLINK=1
else
    HAS_NVLINK=0
fi
echo "HAS_NVLINK: $HAS_NVLINK (detected $NVLINK_COUNT NVLink references)"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${SCRIPT_DIR}/models/qwen2.5-0.5B.sh"

CKPT_ARGS=(
   --hf-checkpoint /root/models/Qwen2.5-0.5B
   --ref-load /root/MegatronFormatedModel/Qwen2.5-0.5B_torch_dist
   --load /root/Qwen2.5-0.5B_slime/
   --save /root/Qwen2.5-0.5B_slime/
   --save-interval 50
)
ROLLOUT_ARGS=(
   --prompt-data /root/gsm8k/train.parquet
   --input-key messages
   --label-key label
   --apply-chat-template
   --rollout-shuffle
   --rm-type math
   # 单步调试：只跑 1 个 rollout，且每个 rollout 只产生 1 个训练样本
   --num-rollout 5
   --rollout-batch-size 2
   --n-samples-per-prompt 4
   --rollout-max-response-len 8
   --rollout-temperature 1
   --global-batch-size 1
)

EVAL_ARGS=(
   # 调试训练 step 时跳过 eval，避免先进入 eval 流程
   --skip-eval-before-train
)
# EVAL_ARGS=(
#    --eval-interval 20
#    --eval-prompt-data gsm8k /root/gsm8k/test.parquet
#    --n-samples-per-eval-prompt 1
#    --eval-max-response-len 8
#    --eval-top-k 1
# )

PERF_ARGS=(
   --tensor-model-parallel-size 1
   --sequence-parallel
   --pipeline-model-parallel-size 1
   --context-parallel-size 1
   --expert-model-parallel-size 1
   --expert-tensor-parallel-size 1
   --use-dynamic-batch-size
   --max-tokens-per-gpu 4096  # 从9216减少到4096
)

GRPO_ARGS=(
   --advantage-estimator grpo
   --use-kl-loss
   --kl-loss-coef 0.00
   --kl-loss-type low_var_kl
   --kl-coef 0.00
   --entropy-coef 0.00
   --eps-clip 0.2
   --eps-clip-high 0.28
)

OPTIMIZER_ARGS=(
   --optimizer adam
   --lr 1e-6
   --lr-decay-style constant
   --weight-decay 0.1
   --adam-beta1 0.9
   --adam-beta2 0.98
)

# WANDB_ARGS=(
#    --use-wandb
#    --wandb-host https://wandb.ai/
#    --wandb-team weirdowww
#    --wandb-project slime-debug
#    --wandb-group qwen2.5-0.5B-gms8k
# )

SGLANG_ARGS=(
   --rollout-num-gpus-per-engine 1
   --sglang-mem-fraction-static 0.4
)

MISC_ARGS=(
   # default dropout in megatron is 0.1
   --attention-dropout 0.0
   --hidden-dropout 0.0
   # should be good for model performance
   --accumulate-allreduce-grads-in-fp32
   --attention-softmax-in-fp32
   # need to comment this when using model with MLA
   --attention-backend flash
)

export CUDA_VISIBLE_DEVICES=3
# launch the master node of ray in container
ray start --head --node-ip-address 127.0.0.1 --num-gpus 1 --disable-usage-stats --num-cpus 16 --ray-debugger-external

# Build the runtime environment JSON with proper variable substitution
RUNTIME_ENV_JSON="{
  \"env_vars\": {
    \"PYTHONPATH\": \"/root/Megatron-LM/\",
    \"CUDA_DEVICE_MAX_CONNECTIONS\": \"1\",
    \"NCCL_NVLS_ENABLE\": \"${HAS_NVLINK}\"
  }
}"
ray job submit --address="http://127.0.0.1:8265" \
   --runtime-env-json="${RUNTIME_ENV_JSON}" \
   -- python3 train.py \
   --actor-num-nodes 1 \
   --actor-num-gpus-per-node 1 \
   --colocate \
   --calculate-per-token-loss \
   --use-slime-router \
   ${MODEL_ARGS[@]} \
   ${CKPT_ARGS[@]} \
   ${ROLLOUT_ARGS[@]} \
   ${OPTIMIZER_ARGS[@]} \
   ${GRPO_ARGS[@]} \
   ${PERF_ARGS[@]} \
   ${EVAL_ARGS[@]} \
   ${SGLANG_ARGS[@]} \
   ${MISC_ARGS[@]}
