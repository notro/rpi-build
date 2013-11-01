#!/bin/bash

set -o pipefail
set -e

WORKDIR=${WORKDIR:-${HOME}}

REPODIR=${WORKDIR}/rpi-firmware

DIR=$(dirname "$0")

[ -z "${1-}" ] && echo "argument missing: branch" && exit 1

WORKDIR=${WORKDIR} python -u ${DIR}/task.py $1 init 2>&1 | tee ${WORKDIR}/init.log
WORKDIR=${WORKDIR} python -u ${DIR}/task.py $1 config 2>&1 | tee ${WORKDIR}/config.log
WORKDIR=${WORKDIR} python -u ${DIR}/task.py $1 build 2>&1 | tee ${WORKDIR}/build.log
WORKDIR=${WORKDIR} python -u ${DIR}/task.py $1 modules_install 2>&1 | tee ${WORKDIR}/modules_install.log
WORKDIR=${WORKDIR} python -u ${DIR}/task.py $1 extra 2>&1 | tee -a ${WORKDIR}/extra.log
WORKDIR=${WORKDIR} python -u ${DIR}/task.py $1 readme update_repo
cp ${WORKDIR}/{init.log,config.log,build.log,modules_install.log,extra.log} ${REPODIR}/extra/
WORKDIR=${WORKDIR} python -u ${DIR}/task.py $1 commit
