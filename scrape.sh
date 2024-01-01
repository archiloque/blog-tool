curl $1 | pandoc --wrap=none -f html -t asciidoc | sed -e 's/’/'\''/g' | sed -e 's/“/"`/g' | sed -e 's/”/`"/g' | code -
