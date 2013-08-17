#!/bin/bash

set -o nounset
set -o errexit

WORKDIR=${HOME}

REPODIR=${WORKDIR}/ftest

DIR=$(dirname "$0")


python -u ${DIR}/task.py init config 2>&1 | tee ${WORKDIR}/release.log
python -u ${DIR}/task.py build 2>&1 | tee ${WORKDIR}/build.log
python -u ${DIR}/task.py modules_install 2>&1 | tee ${WORKDIR}/modules_install.log
python -u ${DIR}/task.py extra update readme 2>&1 | tee -a ${WORKDIR}/release.log


cp ${WORKDIR}/{release.log,build.log,modules_install.log} ${REPODIR}/extra/
