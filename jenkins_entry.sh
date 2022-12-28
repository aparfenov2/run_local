set -ex
set -o pipefail

[ -f "./jenkins_env.sh" ] && {
    . ./jenkins_env.sh
}
# env
DOCKER_IMAGE="ml-py38-gpu-114"
DOCKER_FILE="Dockerfile"
POSITIONAL=("$@")
OTHER_ARGS=()
DOCKER_TI="-i"
[ "${SSH_HOST}" == "local" ] && {
    DOCKER_TI="-ti"
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --train) TRAIN=1;;
        --eval) EVAL=1;;
        --daemon) DOCKER_TI="-d";;
        --docker) RUN_IN_DOCKER=1;;
        --in_docker) IN_DOCKER=1;;
        --build) DOCKER_BUILD=1;;
        --init) PREPARE_ENV=1;;
        --in_eplus) IN_EPLUS=1;;
        --tg) TG=1;;
        --_local_ip) LOCAL_IP="$2"; shift ;;
        --exit) EXIT_AFTER=1;;
        *) OTHER_ARGS+=($1);;
    esac
    shift
done

[ -n "${IN_DOCKER}" ] && {
    [ -f "/cdir/jenkins_env.sh" ] && {
        . /cdir/jenkins_env.sh
    }
}

[ -n "${IN_DOCKER}" ] && {
    echo ========================= IN_DOCKER ============================
}

echo POSITIONAL="${POSITIONAL[@]}"
echo OTHER_ARGS="${OTHER_ARGS[@]}"
echo EXPERIMENT_NAME="${EXPERIMENT_NAME}"
echo RUN_IN_DOCKER=${RUN_IN_DOCKER}
echo IN_DOCKER=${IN_DOCKER}
echo EXIT_AFTER=${EXIT_AFTER}

WORKDIR=$PWD
echo WORKDIR=$WORKDIR


[ -n "${DOCKER_BUILD}" ] && [ -z "${IN_DOCKER}" ] && {
    pushd $PWD
    docker build -t ${DOCKER_IMAGE} -f ./Dockerfile /var/mail
    [ -n "${EXIT_AFTER}" ] && {
        exit 0
    }
    popd
}

[ -n "${TG}" ] && {
    command -v curl >/dev/null 2>&1 || {
        SUDO=""
        [ "$UID" == "0" ] || {
            SUDO="sudo"
        }
        $SUDO apt update && $SUDO apt install -y curl
    }
    LOCAL_HOSTNAME=$(hostname -d)
    if [[ ${LOCAL_HOSTNAME} =~ .*\.amazonaws\.com ]]; then
        LOCAL_IP="$(curl http://169.254.169.254/latest/meta-data/local-ipv4)"
        PUBLIC_IP="$(curl http://169.254.169.254/latest/meta-data/public-ipv4)"
    else
        [ -z "${IN_DOCKER}" ] && {
            # ifconfig is not supported in docker
            LOCAL_IP=$(ifconfig | grep 192.168 | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')
            PUBLIC_IP=$(curl -s ifconfig.me)
        }
    fi
} # [ -n "${TG}" ] && {

[ -n "${RUN_IN_DOCKER}" ] && [ -z "${IN_DOCKER}" ] && {

    # [ -n "${EVAL}" ] && {
        # [ -L models ] && [ -e models ] || {
        #     echo models link not found
        #     exit 1
        # }
        # [ -L data ] && [ -e data ] || {
        #     [ -d data ] || {
        #         echo data link not found
        #         exit 1
        #     }
        # }
    # }

    VOLUMES=()
    for f in $(find . -type l); do
        [ -e "$f" ] && {
            VOLUMES+=("-v $(readlink -f $f):/cdir/$f")
        }
    done

    _RM="--rm"
    [ "${DOCKER_TI}" == "-d" ] && {
        # docker container inspect ${EXPERIMENT_NAME} > /dev/null 2>&1 && {
        #     echo container ${EXPERIMENT_NAME} already exists
        #     exit 0
        # }
        docker rm ${EXPERIMENT_NAME} || true
        _RM=""
    }

    # mkdir .cache || true
    docker run ${DOCKER_TI} ${_RM} \
        --gpus all \
        --network host \
        --shm-size=8g \
        --name ${EXPERIMENT_NAME} \
        ${VOLUMES[@]} \
        -v $PWD:/cdir \
        -v $(readlink -f .app):/app \
        -w /cdir \
        ${DOCKER_IMAGE} bash /cdir/$0 --in_docker --_local_ip ${LOCAL_IP} "${POSITIONAL[@]}"
    exit 0
}


# [ -n "${PREPARE_ENV}" ] && {
#     echo "prepare docker image"
#     bash ./configure.sh
#     echo "image configuration complete!"
#     [ -n "${EXIT_AFTER}" ] && {
#         exit 0
#     }
# }

[ -n "${TG}" ] && {

[ -z "${IN_EPLUS}" ] && {
    set +e
    _3="3"
    [ -n "${IN_DOCKER}" ] && {
        _prefix="/cdir/"
        _3=""
    }
    pip${_3} install telegram-send
    export PATH=/app/.local/bin:$PATH
    # LOCAL_IP=$(ifconfig | grep 192.168 | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')
    telegram-send --config ${_prefix}telegram-send.conf "started ${EXPERIMENT_NAME} at ${LOCAL_IP}"
    bash $0 --in_eplus "${POSITIONAL[@]}"
    errcode=$?
    telegram-send --config ${_prefix}telegram-send.conf "DONE ${EXPERIMENT_NAME}, $errcode at ${LOCAL_IP}"
    exit 0
}
} # [ -n "${TG}" ] && {

# ----------------------------------------------
# --------------- IN DOCKER --------------------
# ----------------------------------------------
PATH="/app/.local/bin:$PATH"

[ -n "${PREPARE_ENV}" ] && {
    curl -sSL https://raw.githubusercontent.com/python-poetry/poetry/master/install-poetry.py | python -
    exit 0
}

. .venv/bin/activate || true

PYTHON="python3 -u" #/opt/conda/bin/python3.
export PYTHONUNBUFFERED=1
# export PYTHONPATH="/cdir/fast-reid"

# nvidia-smi -l 120 --query-gpu=timestamp,memory.used --format=csv | tee gpu.log &

[ -n "${TRAIN}" ] && {
    python main.py train mini --dataroot=nuscenes --logdir=./runs --gpuid=0 2>&1 | tee train.log
    exit 0
}

[ -n "${EVAL}" ] && {
    python main.py viz_model_preds mini --gpuid 0 --modelf=model525000.pt --dataroot=nuscenes --map_folder=nuscenes
    exit 0
}
