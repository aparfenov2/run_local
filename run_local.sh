# set -ex
SSH_HOST=local
SSH_PORT=22
SSH_USER=root
SSH_KEY=
EXPERIMENT_NAME=default_experiment
BRANCH_NAME=develop
REPO_URL=git@github.com:kantengri/counter.git
DELETE_IF_EXIST=false
EXPERIMENT_DIR="$PWD/jenkins_experiments"
SRC_DIR=
INSIDE_HOST=
SRV_WORKDIR=.
SESSION_MANAGER=
FAST_PORT=18000

ARGS=()
OTHER_ARGS=()

while [[ $# -gt 0 ]]
do
case $1 in
    --host)
    SSH_HOST="$2"
    ARGS+=("$1")
    ARGS+=("$2")
    shift # past argument
    shift # past value
    ;;
    --inside_host)
    INSIDE_HOST=1
    shift # past argument
    ;;
    --port)
    SSH_PORT="$2"
    shift # past argument
    shift # past value
    ;;
    --key)
    SSH_KEY="$2"
    shift # past argument
    shift # past value
    ;;
    --user)
    SSH_USER="$2"
    shift # past argument
    shift # past value
    ;;
    -e|--experiment)
    EXPERIMENT_NAME="$2"
    ARGS+=("$1")
    ARGS+=("$2")
    shift # past argument
    shift # past value
    ;;
    --branch)
    BRANCH_NAME="$2"
    ARGS+=("$1")
    ARGS+=("$2")
    shift # past argument
    shift # past value
    ;;
    --src)
    SRC_DIR="$2"
    ARGS+=("$1")
    ARGS+=("$2")
    shift # past argument
    shift # past value
    ;;
    --srv_workdir)
    SRV_WORKDIR="$2"
    shift # past argument
    shift # past value
    ;;
    --manager)
    SESSION_MANAGER="$2"
    shift # past argument
    shift # past value
    ;;
    --url)
    REPO_URL="$2"
    shift # past argument
    shift # past value
    ;;
    --delete)
    ARGS+=("$1")
    DELETE_IF_EXIST=true
    shift # past argument
    ;;
    --fast_upload)
    FAST_UPLOAD=1
    shift # past argument
    ;;
    --artifact)
    ARTIFACT="$2"
    shift # past argument
    shift # past value
    ;;
    --deploy_only)
    DEPLOY_ONLY=1
    shift # past argument
    ;;
    --no_deploy)
    NO_DEPLOY=1
    shift # past argument
    ;;
    *)    # unknown option
    OTHER_ARGS+=("$1")
    shift # past argument
    ;;
esac
done

WORKDIR="${EXPERIMENT_DIR}/${EXPERIMENT_NAME}"
echo ARGS=${ARGS[@]} ${OTHER_ARGS[@]}
echo WORKDIR=$WORKDIR

[ -n "${INSIDE_HOST}" ] && {
    echo ========================= INSIDE_HOST ============================
}

[ -n "${FAST_UPLOAD}" ] && {
    LOCAL_IP=$(ifconfig | grep 192.168 | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')
    # EXTERN_IP=$(dig +short myip.opendns.com @resolver1.opendns.com)
    EXTERN_IP=$(curl ifconfig.me)
    echo LOCAL_IP=${LOCAL_IP}
    echo EXTERN_IP=${EXTERN_IP}
}

function do_scp {
    scp -o LogLevel=error -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $KEYARG -P ${SSH_PORT} $1 ${SSH_USER}@${SSH_HOST}:$2
}

function do_scp_back {
    scp -o LogLevel=error -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $KEYARG -P ${SSH_PORT} ${SSH_USER}@${SSH_HOST}:$1 $2
}

function do_ssh {
    ssh -t -o ControlPath=~/.ssh/master-$$ -o ControlMaster=auto -o ControlPersist=60 -o LogLevel=error -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $KEYARG -p ${SSH_PORT} ${SSH_USER}@${SSH_HOST}
}

function fast_upload {
    [ -z "${FAST_UPLOAD}" ] && {
        do_scp $1 $2
    }
    [ -n "${FAST_UPLOAD}" ] && {
        echo "using fast_upload $1 $2"
        python3 -m http.server -b ${LOCAL_IP} ${FAST_PORT} &
        SRV_PID=$!
        do_ssh << EOF0
        wget -O $2 http://${EXTERN_IP}:${FAST_PORT}/$1
EOF0
        kill ${SRV_PID}
    }
    echo "DONE fast_upload $1 $2"
}

[ "$SSH_HOST" != "local" ] && [ -z "${INSIDE_HOST}" ] && {
    KEYARG=
    [ -n "${SSH_KEY}" ] && {
        KEYARG="-i ${SSH_KEY}"
    }
    # create SRV_WORKDIR
    do_ssh << EOF1
    [ -d "${SRV_WORKDIR}" ] || {
        mkdir -p "${SRV_WORKDIR}"
    }
EOF1
    [ -z "${NO_DEPLOY}" ] && {
        [ -n "${SRC_DIR}" ] && {
            tar zchf src.tgz ${SRC_DIR}
            echo "scp sources"
            fast_upload src.tgz ${SRV_WORKDIR}/src.tgz
        }

        do_scp $0 ${SRV_WORKDIR}
        [ -n "${DEPLOY_ONLY}" ] && {
            echo deploy complete
            exit 0
        }
    }
    do_ssh << EOF2
    cd ${SRV_WORKDIR}
    # set -ex

    function find_screen {
        if screen -ls "\$1" | grep -o "^\s*[0-9]*\.$1[ "$'\t'"](" --color=NEVER -m 1 | grep -oh "[0-9]*\.\$1" --color=NEVER -m 1 -q >/dev/null; then
            screen -ls "\$1" | grep -o "^\s*[0-9]*\.$1[ "$'\t'"](" --color=NEVER -m 1 | grep -oh "[0-9]*\.\$1" --color=NEVER -m 1 2>/dev/null
            return 0
        else
            echo "\$1"
            return 1
        fi
    }

    function exec_in_screen {
        name="\$1"
        command="\$2"
        [ -z "\$name" ] && {
            echo no session name
            exit 1
        }
        screen -dmS \$name bash
        screen -S \$name -X stuff "\$command\n";
    }

    [ "${SESSION_MANAGER}" == "screen" ] && {

        if find_screen "${EXPERIMENT_NAME}" >/dev/null; then
            echo screen session ${EXPERIMENT_NAME} already started
            exit 1
        fi
        exec_in_screen "${EXPERIMENT_NAME}" "bash $0 --inside_host ${ARGS[@]} ${OTHER_ARGS[@]}"
        echo new screen session ${EXPERIMENT_NAME} started
    }
    [ "${SESSION_MANAGER}" == "tmux" ] && {
        tmux has-session -t ${EXPERIMENT_NAME} && {
            echo tmux session ${EXPERIMENT_NAME} already started
            exit 1
        }
        tmux new-session -s ${EXPERIMENT_NAME} -d \; send-keys "echo $PWD && bash $0 --inside_host ${ARGS[@]} ${OTHER_ARGS[@]}" C-m
        echo new tmux session ${EXPERIMENT_NAME} started
    }
    [ -z "${SESSION_MANAGER}" ] && {
        bash $0 --inside_host ${ARGS[@]} ${OTHER_ARGS[@]}
    }
EOF2
    [ -n "$ARTIFACT" ] && {
        do_scp_back ${SRV_WORKDIR}/jenkins_experiments/${EXPERIMENT_NAME}/$ARTIFACT .
    }
    exit 0
}

[ "${DELETE_IF_EXIST}" == "true" ] && {
    echo delete the existing work folder $WORKDIR
    sudo rm -r $WORKDIR || true
}

command -v git >/dev/null 2>&1 || {
    apt update && apt install -y git
}
export GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"

echo PWD=$PWD
_SRC_DIR="$PWD/${SRC_DIR}"
SRC_TGZ=$PWD/src.tgz

[ -d "${WORKDIR}" ] || {
    mkdir -p ${WORKDIR}
    cd ${WORKDIR}
    [ -n "${SRC_DIR}" ] || {
        git clone ${REPO_URL} .
        git checkout ${BRANCH_NAME}
    }
}
cd ${WORKDIR}

[ -n "${SRC_DIR}" ] && {
    [ "$SSH_HOST" != "local" ] && {
        echo "extracting sources"
        sudo tar zxf ${SRC_TGZ} --overwrite --strip 1
    }

    [ "${SSH_HOST}" == "local" ] && {
        echo "using ${_SRC_DIR} as source folder"
        cp -R -T ${_SRC_DIR} ${WORKDIR}
    }
}

[ -n "${SRC_DIR}" ] || {
    git pull
}

echo BRANCH_NAME=\"${BRANCH_NAME}\" > jenkins_env.sh
echo _OTHER_ARGS=\"${OTHER_ARGS[@]}\" >> jenkins_env.sh
echo WORKDIR=\"${WORKDIR}\" >> jenkins_env.sh
echo EXPERIMENT_NAME=\"${EXPERIMENT_NAME}\" >> jenkins_env.sh
echo SSH_HOST=\"${SSH_HOST}\" >> jenkins_env.sh

bash ./jenkins_entry.sh "${OTHER_ARGS[@]}"
