#!/bin/sh

pushd itracker_backup_injector
bundle install
./inject.rb
popd
rm -rf itracker_backup_injector
