#!/usr/bin/env bash

# fail on error
set -e

# Retry 5 times with a wait of 10 seconds between each retry
tryfail() {
    for i in $(seq 1 5);
        do [ $i -gt 1 ] && sleep 10; $* && s=0 && break || s=$?; done;
    (exit $s)
}

# Try multiple keyservers in case of failure
addKey() {
    for server in $(shuf -e ha.pool.sks-keyservers.net \
        hkp://p80.pool.sks-keyservers.net:80 \
        keyserver.ubuntu.com \
        hkp://keyserver.ubuntu.com:80 \
        pgp.mit.edu) ; do \
        if apt-key adv --keyserver "$server" --recv "$1"; then
            exit 0
        fi
    done
    return 1
}

if [ "x${1}" == "x" ]; then
    echo please pass PKGURL as an environment variable
    exit 0
fi

apt-get update
apt-get install -qy --no-install-recommends \
    apt-transport-https \
    curl \
    dirmngr \
    gpg \
    gpg-agent \
    procps \
    libcap2-bin \
    tzdata

# --- temurin-25-jdk (required by unifi.deb on newer Ubuntu) ---
apt install -y wget apt-transport-https gpg
wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor | tee /etc/apt/trusted.gpg.d/adoptium.gpg > /dev/null

echo "deb https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" | tee /etc/apt/sources.list.d/adoptium.list

apt-get update
apt-get install -qy --no-install-recommends \
  temurin-25-jre
# --- end temurin-25-jdk ---

# --- MongoDB (required by unifi.deb on newer Ubuntu) ---
apt-get update
apt-get install -qy --no-install-recommends ca-certificates gnupg

install -d /usr/share/keyrings
curl -fsSL https://pgp.mongodb.com/server-4.4.asc \
  | gpg --dearmor -o /usr/share/keyrings/mongodb-server-4.4.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/mongodb-server-4.4.gpg] \
https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/4.4 multiverse" \
  > /etc/apt/sources.list.d/mongodb-org-4.4.list

apt-get update

# Pin to 4.4 so we never pull an update (unifi wants < 8.1.0)
apt-get install -qy --no-install-recommends \
  mongodb-org-server=4.4.* mongodb-org-shell=4.4.* mongodb-org-mongos=4.4.* mongodb-org-tools=4.4.*

apt-mark hold mongodb-org-server mongodb-org-shell mongodb-org-mongos mongodb-org-tools
# --- end MongoDB ---

echo 'deb https://www.ui.com/downloads/unifi/debian stable ubiquiti' | tee /etc/apt/sources.list.d/100-ubnt-unifi.list
tryfail apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 06E85760C0A52C50

if [ -d "/usr/local/docker/pre_build/$(dpkg --print-architecture)" ]; then
    find "/usr/local/docker/pre_build/$(dpkg --print-architecture)" -type f -exec '{}' \;
fi

curl -L -o ./unifi.deb "${1}"
apt -qy install ./unifi.deb
rm -f ./unifi.deb
chown -R unifi:unifi /usr/lib/unifi
rm -rf /var/lib/apt/lists/*

rm -rf ${ODATADIR} ${OLOGDIR} ${ORUNDIR} ${BASEDIR}/data ${BASEDIR}/run ${BASEDIR}/logs
mkdir -p ${DATADIR} ${LOGDIR} ${RUNDIR}
ln -s ${DATADIR} ${BASEDIR}/data
ln -s ${RUNDIR} ${BASEDIR}/run
ln -s ${LOGDIR} ${BASEDIR}/logs
ln -s ${DATADIR} ${ODATADIR}
ln -s ${LOGDIR} ${OLOGDIR}
ln -s ${RUNDIR} ${ORUNDIR}
mkdir -p /var/cert ${CERTDIR}
ln -s ${CERTDIR} /var/cert/unifi

rm -rf "${0}"
