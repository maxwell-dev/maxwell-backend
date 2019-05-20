#!/usr/bin/env bash

root_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )";
dev_config="${root_dir}/config/vm.dev.args";
prod_config="${root_dir}/config/vm.prod.args";

function resolve_public_ip() {
    public_ip=$(curl -s https://api.ip.la);
    echo ${public_ip};
}

function resolve_private_ip() {
    private_ip=$(
        ifconfig \
        | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' \
        | grep -Eo '([0-9]*\.){3}[0-9]*' \
        | grep -v '127.0.0.1' \
        | head -n 1
    );
    echo ${private_ip};
}

function parse_public_ip() {
    file=$1;
    current_public_ip=$(cat ${file} | grep public_ip | awk '{print $2}');
    echo ${current_public_ip};
}

function parse_private_ip() {
    file=$1;
    current_private_ip=$(cat ${file} | grep private_ip | awk '{print $2}');
    echo ${current_private_ip};
}

function replace_public_ip() {
    file=$1;
    old=$2;
    new=$3;
    os=$(uname);
    if [[ "${os}" = "Linux" ]]; then
        sed -i "s%public_ip[[:space:]]*${old}%public_ip ${new}%g" ${file};
    elif [[ "${os}" == "Darwin" ]]; then
        sed -i "" "s%public_ip[[:space:]]*${old}%public_ip ${new}%g" ${file};
    fi
}

function replace_private_ip() {
    file=$1;
    old=$2;
    new=$3;
    os=$(uname);
    if [[ "${os}" = "Linux" ]]; then
        sed -i "s%private_ip[[:space:]]*${old}%private_ip ${new}%g" ${file};
    elif [[ "${os}" == 'Darwin' ]]; then
        sed -i "" "s%private_ip[[:space:]]*${old}%private_ip ${new}%g" ${file};
    fi
}

function ensure_public_ip_generated() {
    file=$1;
    current_public_ip=$(parse_public_ip ${file});
    if [[ "${current_public_ip}" != "0.0.0.0" ]]; then
        return;
    fi
    resolved_public_ip=$(resolve_public_ip)
    if [[ "${resolved_public_ip}" =~ ^([0-9]*\.){3}[0-9]*$ ]]; then
        replace_public_ip ${file} "0.0.0.0" "${resolved_public_ip}";
    else
        echo "Failed to resolve public ip!"
        exit 1;
    fi
}

function ensure_private_ip_generated() {
    file=$1;
    current_private_ip=$(parse_private_ip ${file});
    echo $current_private_ip
    if [[ "${current_private_ip}" != "0.0.0.0" ]]; then
        return;
    fi
    resolved_private_ip=$(resolve_private_ip)
    echo $resolved_private_ip
    if [[ "${resolved_private_ip}" =~ ^([0-9]*\.){3}[0-9]*$ ]]; then
        replace_private_ip ${file} "0.0.0.0" "${resolved_private_ip}";
    fi
}

ensure_public_ip_generated ${dev_config};
ensure_public_ip_generated ${prod_config};