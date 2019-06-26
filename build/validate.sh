#!/usr/bin/env bash

RED='\033[1;31m'
GREEN='\033[1;32m'
buildResult=1
buildMessage=""
result=0

function runTests {
    echo "Setup for tests..."
    "$TRAVIS_BUILD_DIR/$SHOP_DIR/vendor/bin/install" -r testing -x frontend

    if [ "$?" = 0 ]; then
        buildMessage="${buildMessage}\n${GREEN}Install for testing was successful"
    else
        buildMessage="${buildMessage}\n${RED}Install for testing was not successful"
        result=$((result+1))
    fi

    echo "Running tests..."
    "$TRAVIS_BUILD_DIR/$SHOP_DIR/vendor/bin/codecept" build -c "vendor/spryker-middleware/$MODULE_NAME/"
    "$TRAVIS_BUILD_DIR/$SHOP_DIR/vendor/bin/codecept" run -c "vendor/spryker-middleware/$MODULE_NAME/"
    if [[ "$?" = 0 ]]; then
        buildMessage="${buildMessage}\n${GREEN}Tests are passing"
    else
        buildMessage="${buildMessage}\n${RED}Tests are failing"
        result=$((result+1))
    fi
    cd "$TRAVIS_BUILD_DIR/$SHOP_DIR"
    echo "Tests finished"

    return $result
}

function checkArchRules {
    echo "Running Architecture sniffer..."
    errors=`vendor/bin/phpmd "vendor/spryker-middleware/$MODULE_NAME/src" text vendor/spryker/architecture-sniffer/src/ruleset.xml --minimumpriority=2 | grep -v __construct`

    if [[ "$errors" = "" ]]; then
        buildMessage="$buildMessage\n${GREEN}Architecture sniffer reports no errors"
    else
        errorsCount=`echo "$errors" | wc -l`
        echo -e "$errors"
        buildMessage="$buildMessage\n${RED}Architecture sniffer reports $errorsCount error(s)"
    fi
}

function checkCodeSniffRules {
    licenseFile="$TRAVIS_BUILD_DIR/.license"
    if [[ -f "$licenseFile" ]]; then
        echo "Preparing correct license for code sniffer..."
        cp "$licenseFile" "$TRAVIS_BUILD_DIR/$SHOP_DIR/.license"
    fi

    echo "Running code sniffer..."
    errors=`vendor/bin/console code:sniff:style "vendor/spryker-middleware/$MODULE_NAME/src"`
    errorsPresent=$?

    if [[ "$errorsPresent" = "0" ]]; then
        buildMessage="$buildMessage\n${GREEN}Code sniffer reports no errors"
    else
        echo -e "$errors"
        buildMessage="$buildMessage\n${RED}Code sniffer reports some error(s)"
    fi
}

function checkPHPStan {
    echo "Running PHPStan..."
    errors=`php -d memory_limit=2048M vendor/bin/phpstan analyze -c phpstan.neon "vendor/spryker-middleware/$MODULE_NAME/src" -l 2`
    errorsPresent=$?

    if [[ "$errorsPresent" = "0" ]]; then
        buildMessage="$buildMessage\n${GREEN}PHPStan reports no errors"
    else
        echo -e "$errors"
        buildMessage="$buildMessage\n${RED}PHPStan reports some error(s)"
    fi
}

function checkDependencyViolationFinder {
    echo "Running DependencyViolationFinder"
    errors=`vendor/bin/console dev:dependency:find "SprykerMiddleware.$MODULE_NAME" -vvv`
    errorsPresent=$?

    if [[ "$errorsPresent" = "0" ]]; then
        buildMessage="$buildMessage\n${GREEN}DependencyViolationFinder reports no errors"
    else
        echo -e "$errors"
        buildMessage="$buildMessage\n${RED}DependencyViolationFinder reports some error(s)"
    fi
}

function checkWithLatestShop {
    echo "Checking module with latest $PRODUCT_NAME..."

    composer config repositories.middlewaremodule path "$TRAVIS_BUILD_DIR/$MODULE_DIR"
    composer update --with-all-dependencies
    composer require "spryker-middleware/$MODULE_NAME @dev" --prefer-source
    result=$?

    if [[ "$result" = 0 ]]; then
        buildMessage="${buildMessage}\n${GREEN}$MODULE_NAME is compatible with the modules used in $PRODUCT_NAME"
        if runTests; then
            buildResult=0
            checkLatestVersionOfModuleWithShop
        fi
    else
        buildMessage="${buildMessage}\n${RED}$MODULE_NAME is not compatible with the modules used in $PRODUCT_NAME"
        checkLatestVersionOfModuleWithShop
    fi
}

function checkLatestVersionOfModuleWithShop {
    echo "Merging composer.json dependencies..."
    updates=`php "$TRAVIS_BUILD_DIR/middleware-ci/build/merge-composer.php" "$TRAVIS_BUILD_DIR/$MODULE_DIR/composer.json" composer.json "$TRAVIS_BUILD_DIR/$MODULE_DIR/composer.json"`
    if [[ "$updates" = "" ]]; then
        buildMessage="${buildMessage}\n${GREEN}$MODULE_NAME is compatible with the latest version of modules used in $PRODUCT_NAME"
        return
    fi

    buildMessage="${buildMessage}\nUpdated dependencies in module to match $PRODUCT_NAME\n$updates"
    echo "Installing module with updated dependencies..."
    composer require "spryker-middleware/$MODULE_NAME @dev" --prefer-source

    result=$?
    if [[ "$result" = 0 ]]; then
        buildMessage="${buildMessage}\n${GREEN}$MODULE_NAME is compatible with the latest version of modules used in $PRODUCT_NAME"
        runTests
    else
        buildMessage="${buildMessage}\n${RED}$MODULE_NAME is not compatible with the latest version of modules used in $PRODUCT_NAME"
    fi
}

updatedFile="$TRAVIS_BUILD_DIR/$SHOP_DIR/vendor/codeception/codeception/src/Codeception/Application.php"
grep APPLICATION_ROOT_DIR "$updatedFile"
if [[ $? = 1 ]]; then
    echo "define('APPLICATION_ROOT_DIR', '$TRAVIS_BUILD_DIR/$SHOP_DIR');" >> "$updatedFile"
fi

cd $SHOP_DIR
checkWithLatestShop

if [[ -d "vendor/spryker-middleware/$MODULE_NAME/src" ]]; then
    checkArchRules
    checkCodeSniffRules
    checkPHPStan

    # will be added:
    #checkDependencyViolationFinder
fi

echo -e "$buildMessage"
exit $buildResult