@echo off
ruby %~dp0\convert_table_to_dot.rb '%~1' map.dot
dot -Tsvg -o map.svg map.dot
dot -Tpdf -o map.pdf map.dot

