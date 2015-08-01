TESTS = ./test.js #$(shell find tests -type f -name test-*)
-RELEASE_DIR := out/release/
-COVERAGE_DIR := out/test/
-RELEASE_COPY := lib
-COVERAGE_COPY := lib tests


-BIN_MOCHA := ./node_modules/.bin/mocha
-BIN_ISTANBUL := ./node_modules/.bin/istanbul
-BIN_COFFEE := ./node_modules/coffee-script/bin/coffee
#-BIN_YAML := ./node_modules/.bin/yaml2json -sp

#-TESTS = $(shell find tests -type f -name test-*)
-TESTS           := $(sort $(TESTS))

-COFFEE_LIB := $(shell find lib -type f -name '*.coffee')
-COFFEE_TEST := $(shell find tests -type f -name 'test-*.coffee')

-COFFEE_RELEASE := $(addprefix $(-RELEASE_DIR),$(-COFFEE_LIB) )

-COFFEE_COVERAGE := $(-COFFEE_LIB)
-COFFEE_COVERAGE += $(-COFFEE_TEST)
-COFFEE_COVERAGE := $(addprefix $(-COVERAGE_DIR),$(-COFFEE_COVERAGE) )

-COVERAGE_TESTS := $(addprefix $(-COVERAGE_DIR),$(-TESTS))
-COVERAGE_TESTS := $(-COVERAGE_TESTS:.coffee=.js)

default: dev

json:
	@echo "make package.json"
	#@$(-BIN_YAML) ./package.yaml


dev: clean json
	@$(-BIN_MOCHA) \
		--colors \
		--compilers coffee:coffee-script/register \
		--reporter list \
		--growl \
		$(-TESTS)

test-watch: json
	@$(-BIN_MOCHA) \
		--compilers coffee:coffee-script/register \
		--reporter tap \
		-w \
		$(-TESTS)
	
test: json
	@$(-BIN_MOCHA) \
		--compilers coffee:coffee-script/register \
		--reporter tap \
		$(-TESTS)

release: dev
	@echo 'copy files'
	@mkdir -p $(-RELEASE_DIR)
	@cp -r $(-RELEASE_COPY) $(-RELEASE_DIR)

	@echo "compile coffee-script files"
	@$(-BIN_COFFEE) -cb $(-COFFEE_RELEASE)
	@rm -f $(-COFFEE_RELEASE)

	@echo "all codes in \"$(-RELEASE_DIR)\""

-pre-test-cov: clean json
	@echo 'copy files'
	@mkdir -p $(-COVERAGE_DIR)

	@rsync -av . $(-COVERAGE_DIR) --exclude out --exclude .git --exclude node_modules
	@rsync -av ./node_modules $(-COVERAGE_DIR)
	@$(-BIN_COFFEE) -cb out/test
	@find ./out/test -path ./out/test/node_modules -prune -o -name "*.coffee" -exec rm -rf {} \;

test-cov: -pre-test-cov
	@cd $(-COVERAGE_DIR) && \
		$(-BIN_ISTANBUL) cover ./node_modules/.bin/_mocha -- -u bdd -R tap --compilers coffee:coffee-script/register $(patsubst $(-COVERAGE_DIR)%, %, $(-COVERAGE_TESTS)) && \
	  $(-BIN_ISTANBUL) report html

test-lcov: -pre-test-cov
	@cd $(-COVERAGE_DIR) && \
		$(-BIN_ISTANBUL) cover ./node_modules/.bin/_mocha --report lcovonly -- -R spec --compilers coffee:coffee-script/register $(patsubst $(-COVERAGE_DIR)%, %, $(-COVERAGE_TESTS)) && \
		cat ./coverage/lcov.info | ./node_modules/coveralls/bin/coveralls.js

.-PHONY: default

clean:
	@echo 'clean'
	@-rm -fr out
	#@-rm -f package.json
	@-rm -f coverage.html
