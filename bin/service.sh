#!/usr/bin/env bash

root_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )";
${root_dir}/_build/default/rel/maxwell_backend_prod/bin/maxwell_backend_prod $1