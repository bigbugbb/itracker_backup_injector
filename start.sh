#!/bin/bash

pushd ./itracker_backup_injector
./inject.rb
popd
rm -rf itracker_backup_injector
