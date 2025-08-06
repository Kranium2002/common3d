#!/bin/bash
#SBATCH -J 07-06_17-22-44_CO3D_NeMo_Rec_slurm
#SBATCH --nodes 1
#SBATCH --ntasks-per-node 1
#SBATCH --time 24:00:00
#SBATCH --cpus-per-task 8
#SBATCH --gres gpu:1
#SBATCH --mem 40gb
#SBATCH --requeue
#SBATCH --open-mode=append # append|truncate
#SBATCH -o /work/dlclarge2/mathurv-mathurv-cv1project/common3d/home/slurm_jobs/%x_%j.o # x=job_name j=job_id
#SBATCH --mail-type=FAIL  # END,FAIL,ALL # (recive mails about end and timeouts/crashes of your job)
#SBATCH --signal=B:SIGUSR1@60

#SBATCH --partition dllabdlc_gpu-rtx2080


CUDA_HOME=/usr/local/cuda-12.4
CUDA_VERSION=$(basename "${CUDA_HOME}")
# PATH=${CUDA_HOME}/bin:${PATH}
# LD_LIBRARY_PATH=${CUDA_HOME}/lib64:${LD_LIBRARY_PATH}
# export PATH
# export LD_LIBRARY_PATH
export CUDA_HOME
export CPATH=$CPATH:${CUDA_HOME}/targets/x86_64-linux/include # pycuda requires this
export LIBRARY_PATH=$LIBRARY_PATH:${CUDA_HOME}/targets/x86_64-linux/lib # pycuda requires this

HTTP_PROXY=http://tfproxy.informatik.intra.uni-freiburg.de:8080
HTTPS_PROXY=http://tfproxy.informatik.intra.uni-freiburg.de:8080
http_proxy=http://tfproxy.informatik.intra.uni-freiburg.de:8080
https_proxy=http://tfproxy.informatik.intra.uni-freiburg.de:8080
export HTTP_PROXY
export HTTPS_PROXY
export http_proxy
export https_proxy
# HTTP_PROXY=http://tfsquid.informatik.intra.uni-freiburg.de:8080
# HTTPS_PROXY=http://tfsquid.informatik.intra.uni-freiburg.de:8080
# export HTTP_PROXY
# export HTTPS_PROXY

# echo PATH=${PATH}
# echo LD_LIBRARY_PATH=${LD_LIBRARY_PATH}
echo CUDA_HOME=${CUDA_HOME}

echo "Getting the lock."
PATH_LOCK="/work/dlclarge1/sommerl-od3d/common3d/installing.txt"
exec 200>${PATH_LOCK}
flock 200
echo "Got the lock."

# while [[ -e "/work/dlclarge1/sommerl-od3d/common3d/installing.txt" ]]; do
#     sleep 3
#     echo "waiting for installing.txt file to disappear."
# done
# touch "/work/dlclarge1/sommerl-od3d/common3d/installing.txt"

# Setup Repository
if [[ -d "/work/dlclarge1/sommerl-od3d/common3d" ]]; then
    echo "OD3D is already cloned to /work/dlclarge1/sommerl-od3d/common3d."
else
    git clone git@github.com:GenIntel/common3d.git /work/dlclarge1/sommerl-od3d/common3d
fi

cd /work/dlclarge1/sommerl-od3d/common3d


git fetch
git checkout main
git pull
            

git submodule init
git submodule update
git submodule foreach 'git fetch origin; git checkout $(git rev-parse --abbrev-ref HEAD); git reset --hard origin/$(git rev-parse --abbrev-ref HEAD); git submodule update --recursive; git clean -dfx'
            

# Install OD3D in venv
VENV_NAME="venv_od3d_${CUDA_VERSION}"
export VENV_NAME
if [[ -d "${VENV_NAME}" ]]; then
    echo "Venv already exists at /work/dlclarge1/sommerl-od3d/common3d/${VENV_NAME}."
    source /work/dlclarge1/sommerl-od3d/common3d/${VENV_NAME}/bin/activate
else
    echo "Creating venv at /work/dlclarge1/sommerl-od3d/common3d/${VENV_NAME}."
    python3 -m venv /work/dlclarge1/sommerl-od3d/common3d/${VENV_NAME}
    source /work/dlclarge1/sommerl-od3d/common3d/${VENV_NAME}/bin/activate
fi


pip install pip --upgrade
pip install wheel

if [[ /usr/local/cuda-12.4 == *"12"* ]]; then
    echo "installing for CUDA 12"
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124
    pip install pytorch3d==0.7.8+pt2.5.1cu124 --extra-index-url https://miropsota.github.io/torch_packages_builder
    pip install torch_cluster -f https://data.pyg.org/whl/torch-2.5.1+cu124.html
    pip install kaolin==0.17.0 -f https://nvidia-kaolin.s3.us-east-2.amazonaws.com/torch-2.5.1_cu124.html
else
    echo "installing for CUDA 11"
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu117
    pip install pytorch3d@git+https://github.com/facebookresearch/pytorch3d@stable
    # pip install --no-index --no-cache-dir pytorch3d -f https://dl.fbaipublicfiles.com/pytorch3d/packaging/wheels/py310_cu117_pyt1131/download.html
    pip install torch-cluster -f https://data.pyg.org/whl/torch-2.0.1+cu117.html
    pip install kaolin==0.17.0 -f https://nvidia-kaolin.s3.us-east-2.amazonaws.com/torch-2.0.1_cu117.html
fi

pip install -e /work/dlclarge1/sommerl-od3d/common3d
            

# rm "${PATH_LOCK}"
exec 200>&- # free lock

od3d debug hello-world

trap "scontrol requeue ${SLURM_JOB_ID}" SIGUSR1

od3d bench single-local -c /work/dlclarge2/mathurv-mathurv-cv1project/common3d/home/tmp/config_07-06_17-22-44_CO3D_NeMo_Rec_slurm.yaml &

PID=$!
wait "${PID}"

EXITCODE="$?"
export EXITCODE

echo "${EXITCODE}"


if [[ "${EXITCODE}" -eq "1" ]]; then
    echo "requeuing due to exit code equals 1..."
    scontrol requeue ${SLURM_JOB_ID}
fi
            

exit 0
        