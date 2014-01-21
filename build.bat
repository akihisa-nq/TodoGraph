@echo off
ruby convert_table_to_dot.rb "table*.txt"
dot -Tsvg -o map.svg map.dot
dot -Tpdf -o map.pdf map.dot
rm *~
pause