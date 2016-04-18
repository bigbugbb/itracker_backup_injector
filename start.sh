#!/bin/sh

sudo apt-get install libpq-dev
bundle install
./inject.rb
popd
# rm -rf itracker_backup_injector
