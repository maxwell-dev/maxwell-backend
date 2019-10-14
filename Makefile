.PHONY : default compile release-dev release-prod run test clean

REBAR=rebar3

default: run

compile:
	${REBAR} get-deps
	${REBAR} compile

release-dev: compile
	${REBAR} release -n maxwell_backend_dev

release-prod: compile
	${REBAR} release -n maxwell_backend_prod

run: release-dev
	_build/default/rel/maxwell_backend_dev/bin/maxwell_backend_dev console

test:
	ERL_FLAGS="-args_file config/vm.dev.args" ${REBAR} eunit

clean:
	${REBAR} clean
