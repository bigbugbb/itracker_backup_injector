#!/bin/sh

rvm use 2.3
bundle install
./inject.rb
