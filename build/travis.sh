echo "Version of CI scripts:"
cd middleware-ci
git log | head -1
cd ..

echo "Moving module to subfolder..."
if [[ *$TRAVIS_EVENT_TYPE* = 'cron' ]]; then git checkout $(git tag | tail -n 1); fi
mkdir $MODULE_DIR
ls -1 | grep -v ^$MODULE_DIR | grep -v ^middleware-ci | xargs -I{} mv {} $MODULE_DIR

echo "Cloning Demo Shop..."
git clone https://github.com/spryker/demoshop.git $SHOP_DIR
cd $SHOP_DIR
composer self-update && composer --version
composer config repositories.logger git https://github.com/spryker-middleware/logger.git
composer install --no-interaction
mkdir -p data/DE/logs
chmod -R 777 data/
./config/Shared/ci/travis/install_elasticsearch.sh

cat config/Shared/ci/travis/postgresql_ci.config >> config/Shared/ci/travis/config_ci.php
cp config/Shared/ci/travis/config_ci.php config/Shared/config_default-devtest_DE.php

namespacesFile="$TRAVIS_BUILD_DIR/middleware-ci/build/.namespaces"
if [ -f "$namespacesFile" ]; then
    echo "Preparing config namespaces..."
    cat "$namespacesFile" >> config/Shared/config_default-devtest_DE.php
fi

cp config/Shared/ci/travis/params_test_env.sh deploy/setup/params_test_env.sh
cd ..

chmod a+x ./middleware-ci/build/travis.sh

./middleware-ci/build/validate.sh
