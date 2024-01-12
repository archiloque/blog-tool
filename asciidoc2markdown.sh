asciidoctor -b docbook --out-file - README.asciidoc | pandoc -f docbook -t markdown_strict | code -
