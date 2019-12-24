#!/bin/bash

find . -type f -print0 | while IFS= read -r -d '' file
do
	extention=$( echo "$file" | rev | cut -d'.' -f 1 | rev )
	if [ "$extention" != "md5" && "$extention" != "json" ] && "$extention" != "sh" ]; then
		md5sum=$(md5sum -b "$file")
		md5=$( echo "$md5sum" | cut -d " " -f 1 )
		echo $file
		echo "$md5" > "$file.md5"
	fi
done
