#!/bin/sh
ruby convert_table_to_dot.rb "table*.txt"
dot -Tsvg -o map.svg map.dot
rm -f *~
