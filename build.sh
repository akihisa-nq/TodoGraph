#!/bin/sh
ruby convert_table_to_dot.rb "$1" map.dot
dot -Tsvg -o map.svg map.dot
rm -f *~
