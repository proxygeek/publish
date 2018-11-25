#!/usr/bin/env bash

# ==============================================================================
# Change Log:
# -----------------  Carried Over --------------------
# 1. Generate directory level htmls - a collection of posts with their excerpts : DONE
# 2. Fix the link to the sections: DONE
# 5. Support markdown format parsing within shell or using standard perl script: DONE
# ---------------Planned in this version --------------
# 4. Refactor the code to remove redundant logic and restructure for clarity
# -----------------  Next Version --------------------
# 3. Fix the top level index.html
# ==============================================================================

topdir=$(pwd)
scriptdir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

# configuration: site level config and files / vars =============================================

# Source configuration file if it exists in the project directory
if [ -f "$topdir/_config.sh" ]; then
  . "$topdir/_config.sh"
fi

metadata_file="metadata.txt" # search for this file in each section directory for section-wide metadata

site_title=${site_title:-"My default sitename"}
# echo "\nsite_title is $site_title"
site_sub_title=${site_sub_title:-"My default subtitle"}
# echo "\nsite_title is $site_sub_title"
theme_dir=${theme_dir:-"theme3"}
# display a toggle button to show/hide the text
text_toggle=${text_toggle:-true}
social_button=${social_button:-true}


# declare any sub-routines (functions) here ================================================

# $1: template, $2: {{ variable name }}, $3: replacement string
template () {
	# remove spaces from the 2nd arguement to template function call
	key=$(echo "$2" | tr -d '[:space:]')
	
	# replace all "/" in $3 (3rd arguement) with "\/" 
	value=$(echo $3 | sed -e 's/\\/\\\\/g' -e 's/\//\\\//g' -e 's/&/\\\&/g') # escape sed input
	# replace all instaces of {{some_key}} in template, i.e $1, with {{corresponding_value}}
	echo "$1" | sed "s/{{$key}}/$value/g; s/{{$key:[^}]*}}/$value/g"
}

# if on cygwin, transforms given param to windows style path
winpath () {
	if command -v cygpath >/dev/null 2>&1
	then
		cygpath -m "$1"
	else
		echo "$1"
	fi
}

cleanup() {
	# remove any ffmpeg log/temp files
	rm -f ffmpeg*.log
	rm -f ffmpeg*.mbtree
	rm -f ffmpeg*.temp

	if [ -d "$scratchdir" ]
    then
        rm -r "$scratchdir"
    fi

	if [ -e "$output_url" ]
	then
		rm -f "$output_url"
	fi

	exit
}


scratchdir=$(mktemp -d 2>/dev/null || mktemp -d -t 'exposetempdir')
scratchdir=$(winpath "$scratchdir")

if [ -z "$scratchdir" ]
then
	echo "Could not create scratch directory" >&2; exit 1;
fi

chmod -R 740 "$scratchdir"

trap cleanup EXIT INT TERM


# script starts here
# Scan directory structure and store required variables ========================================

paths=() # relevant non-empty dirs in $topdir; () indicates an empty list
nav_name=() # a front-end friendly label for each item in paths[], with numeric prefixes stripped
nav_depth=() # depth of each navigation item
nav_type=() # 0 = structure, 1 = leaf. Where a leaf directory is a section of images
nav_url=() # a browser-friendly url for each path, relative to _site
nav_count=() # the number of images in each section, or -1 if not a leaf

section_files=() # a flat list of all section images and videos
section_nav=() # index of nav item the section image belongs to
section_url=() # url-friendly name of each image
section_type=() # 0 = image, 1 = video, 2 = image sequence


# scan working directory to populate $nav variables
root_depth=$(echo "$topdir" | awk -F"/" "{ print NF }")

output_url=""

printf "Scanning directories"

while read node
do
	printf "."

	if [ "$node" = "$topdir/_site" ]
	then
		continue
	fi

	node_depth=$(echo "$node" | awk -F"/" "{ print NF-$root_depth }")
	# echo "\n node_depth for $node is $node_depth \n"

	# ignore empty directories
	if find "$node" -maxdepth 0 -empty | read v
	then
		continue
	fi

	# extract the filename from filepath (node) and remove all leading numerals, spaces, etc
	node_name=$(basename "$node" | sed -e 's/^[0-9]*//' | sed -e 's/^[[:space:]]*//;s/[[:space:]]*$//')
	if [ -z "$node_name" ]
	then
		node_name=$(basename "$node")
	fi

	dircount=$(find "$node" -maxdepth 1 -type d ! -path "$node" ! -path "$node*/_*" | wc -l)
	dircount_sequence=$(find "$node" -maxdepth 1 -type d ! -path "$node" ! -path "$node*/_*" ! -path "$node/*$sequence_keyword*" | wc -l)

	if [ "$dircount" -gt 0 ]
	then
		if [ -z "$sequence_keyword" ] || [ "$dircount_sequence" -gt 0 ]
		then
			node_type=0 # dir contains other dirs, it is not a leaf
		else
			node_type=1 # dir contains other dirs, but they are imagesequence dirs which are not galleries
		fi
		# echo "   node_type for $node is $node_type # 0: Has sub-directories  1: has sub-directories with image sequences \n "
	else
		if [ ! -z "$sequence_keyword" ] && [ $(echo "$node_name" | grep "$sequence_keyword" | wc -l) -gt 0 ]
		then
			# echo "   $node is is an imagesequence dir, it is in effect a video. Do not add to the path list \n "
			continue # dir is an imagesequence dir, it is in effect a video. Do not add to the path list
		else
			node_type=1 # does not contain other dirs, and is not image sequence. It is a leaf
		fi
		# echo "   node_type for $node is $node_type #  \n "
	fi

	paths+=("$node")
	nav_name+=("$node_name")
	nav_depth+=("$node_depth")
	nav_type+=("$node_type")
done < <(find "$topdir" -type d ! -path "$topdir*/_*" | sort)

echo ".   \n  ............... paths / files identified ................ \n "
echo ".   \n  paths: $paths \n "
echo ".   \n  nav_name: $node_name \n "
echo ".   \n  nav_depth: $node_depth \n "
echo ".   \n  nav_type: $node_type \n "
echo ".   \n  ............................................................... \n\n "


# re-create directory structure under a new subfolder - _site - for the website ===================================
mkdir -p "$topdir/_site"

dir_stack=()
url_rel=""
nav_url+=(".") # first item in paths will always be $topdir

printf "\nPopulating nav"

for i in "${!paths[@]}"
do
	printf "."

	if [ "$i" = 0 ]
	then
		continue
	fi

	path="${paths[i]}"
	if [ "$i" -gt 1 ]
	then
		if [ "${nav_depth[i]}" -gt "${nav_depth[i-1]}" ]
		then
			# push onto stack when we go down a level
			dir_stack+=("$url_rel")
		elif [ "${nav_depth[i]}" -lt "${nav_depth[i-1]}" ]
		then
			# pop stack with respect to current level
			diff="${nav_depth[i-1]}"
			while [ "$diff" -gt "${nav_depth[i]}" ]
			do
				unset dir_stack[${#dir_stack[@]}-1]
				((diff--))
			done
		fi
	fi

	url_rel=$(echo "${nav_name[$i]}" | sed 's/[^ a-zA-Z0-9]//g;s/ /-/g' | tr '[:upper:]' '[:lower:]')

	url=""
	for u in "${dir_stack[@]}"
	do
		url+="$u/"
	done

	url+="$url_rel"
	mkdir -p "$topdir/_site/$url"

	nav_url+=("$url")
	
	section_nav+=("$i") # copied here from the "store file and type for later use" section for navigation html generation
	
done


# create the html code for the sidebar ================================================
# build main navigation
navigation=""

# write html menu via depth first search
depth=1
prevdepth=0

remaining="${#paths[@]}"
parent=-1

while [ "$remaining" -gt 1 ]
do
	for j in "${!paths[@]}"
	do
		if [ "$depth" -gt 1 ] && [ "${nav_depth[j]}" = "$prevdepth" ]
		then
			parent="$j"
		fi
		
		if [ "$parent" -lt 0 ] && [ "${nav_depth[j]}" = 1 ]
		then
			if [ "${nav_type[j]}" = 0 ]
			then
				navigation+=""
			else
				gindex=0
				for k in "${!section_nav[@]}"
				do
					if [ "${section_nav[k]}" = "$j" ]
					then
						gindex="$k"
						break
					fi
				done
				navigation+="<a class="sidebar-nav-item" href=\"{{basepath}}${nav_url[j]}\">${nav_name[j]}</a>"
			fi
			((remaining--))
		elif [ "${nav_depth[j]}" = "$depth" ]
		then
			if [ "${nav_type[j]}" = 0 ]
			then
				substring="<li><span class=\"label\">${nav_name[j]}</span><ul>{{marker$j}}</ul></li>{{marker$parent}}"
			else
				gindex=0
				for k in "${!section_nav[@]}"
				do
					if [ "${section_nav[k]}" = "$j" ]
					then
						gindex="$k"
						break
					fi
				done
				substring="<a class="sidebar-nav-item" href=\"{{basepath}}${nav_url[j]}\">${nav_name[j]}</a>"
			fi
			navigation=$(template "$navigation" "marker$parent" "$substring")
			((remaining--))
		fi
	done
	((prevdepth++))
	((depth++))
done

nav_template=$(cat "$scriptdir/$theme_dir/nav-template.html")
nav_html="$nav_template"

nav_html=$(template "$nav_html" navigation "$navigation")


# =============================================================================
# read each relevant file in the directory structure and store the processed content for future use =====
# TODO: might be better to create corresponding html files while looping through the files, in the same loop
printf "\nReading files"


# read in each file to populate $section variables
for i in "${!paths[@]}"
do
	nav_count[i]=-1
	if [ "${nav_type[i]}" -lt 1 ]
	then
		continue
	fi

	dir="${paths[i]}"
	name="${nav_name[i]}"
	url="${nav_url[i]}"

	mkdir -p "$topdir"/_site/"$url"

	index=0

	# loop over found files
	while read file
	do

		printf "."

		filename=$(basename "$file")
		filedir=$(dirname "$file")
		filepath=$(winpath "$file")
		
		# echo ".. \n Currently processing $filename  ...... \n"

		trimmed=$(echo "${filename%.*}" | sed -e 's/^[[:space:]0-9]*//;s/[[:space:]]*$//')

		if [ -z "$trimmed" ]
		then
			trimmed=$(echo "${filename%.*}")
		fi

		image_url=$(echo "$trimmed" | sed 's/[^ a-zA-Z0-9]//g;s/ /-/g' | tr '[:upper:]' '[:lower:]')

		if [ -d "$file" ] && [ $(echo "$filename" | grep "$sequence_keyword" | wc -l) -gt 0 ]
		then
			format="sequence"
			image=$(find "$file" -maxdepth 1 ! -path "$file" -iname "*.md" -o -iname "*.post" | sort | head -n 1)
		else
			extension=$(echo "${filename##*.}" | tr '[:upper:]' '[:lower:]')

			# we'll trust that extensions aren't lying
			if [ "$extension" = "md" ] || [ "$extension" = "post" ] || [ "$extension" = "txt" ]
			then
				format="$extension"
			else
				# could be a video file
				if [ "$video_enabled" = false ]
				then
					continue
				fi

				found=false
				for e in "${video_extensions[@]}"
				do
					if [ "$e" = "$extension" ]
					then
						found=true
						break
					fi
				done

				if [ "$found" = false ]
				then
					LC_ALL=C file -ib "$filename" | grep video >/dev/null || continue # not image or video or sequence, ignore
				fi

				format="video"
			fi
		fi


		((index++))

		# store file and type for later use
		section_files+=("$file")
		section_nav+=("$i")
		section_url+=("$image_url")

		if [ "$format" = "sequence" ]
		then
			section_type+=(2)
		elif [ "$format" = "video" ]
		then
			section_type+=(1)
		else
			section_type+=(0)
		fi
	done < <(find "$dir" -maxdepth 1 ! -path "$dir" ! -path "$dir*/_*" | sort)

	nav_count[i]="$index"
done


# build html file for each post ====================================================
# echo "scriptdir/theme_dir/template.html is $scriptdir/$theme_dir/template.html"

# template=$(cat "$scriptdir/$theme_dir/template.html")
post_template=$(cat "$scriptdir/$theme_dir/post-template.html")
dir_template=$(cat "$scriptdir/$theme_dir/dir-template.html")

section_index=0
firsthtml=""
firstpath=""

printf "\nBuilding HTML"

for i in "${!paths[@]}"
do
	if [ "${nav_type[i]}" -lt 1 ]
	then
		continue
	fi

	echo ".. \n Currently in ${paths[i]} directory ... \n"
	
	dir_html="$nav_html""$dir_template"
	all_posts_excerpts=""
	dir_tag_cloud=""
	
	section_metadata=""
	if [ -e "${paths[i]}/$metadata_file" ]  # -e returns true if the arguement exists; checking if the metadata file exists for this dir
	then
		section_metadata=$(cat "${paths[i]}/$metadata_file")
	fi

	j=0
	while [ "$j" -lt "${nav_count[i]}" ] # looping through all the posts in current directory ${paths[i]}
	do
	
		html="$nav_html""$post_template"
	
		printf "." # show progress

		k=$((j+1))
		file_path="${section_files[section_index]}"
		file_type="${section_type[section_index]}"
		
		# try to find a text file with the same name
		filename=$(basename "$file_path")
		filename="${filename%.*}"

		filedir=$(dirname "$file_path")
		
		echo " .. \n Line 453: file_path is $file_path \n file_type is $file_type \n filename is $filename \n filedir is $filedir \n "

		type="image"
		if [ "${section_type[section_index]}" -gt 0 ]
		then
			type="video"
		fi

		#textfile=$(find "$filedir/$filename".post "$filedir/$filename".md ! -path "$file_path" -print -quit 2>/dev/null) #original code
		textfile=$(find "$filedir/$filename".post "$filedir/$filename".md ! -path "$filedir" -print -quit 2>/dev/null) #modified; same as $file_path

		metadata=""
		content=""
		if LC_ALL=C file "$textfile" | grep -q text
		then
			# if there are two lines "---", the lines preceding the second "---" are assumed to be metadata
			text=$(cat "$textfile" | tr -d $'\r')
			text=${text%$'\n'}
			metaline=$(echo "$text" | grep -n -m 2 -- "^---$" | tail -1 | cut -d ':' -f1) # line number after which actual post content starts

			if [ "$metaline" ]
			then
				sumlines=$(echo "$text" | wc -l)
				taillines=$((sumlines-metaline)) # Working fine

				metadata=$(head -n "$metaline" "$textfile")
				content=$(tail -n "$taillines" "$textfile")
			else
				metadata=""
				content=$(echo "$text")
			fi
		fi
		
		# if perl available, pass content through markdown parser
		if command -v perl >/dev/null 2>&1
		then
			content=$(perl "$scriptdir/Markdown_1.0.1/Markdown.pl" --html4tags <(echo "$content"))
		fi
		
		echo " . \n ............................... \n post content is : \n $content \n ........................ \n "
		
		metadata+=$'\n'
		metadata+="$section_metadata"
		metadata+=$'\n'

		# post=$(template "$post" postcontent "$content")

		# reading key value pairs from the post metadata and updating the same in $post
		while read line
		do
			key=$(echo "$line" | cut -d ':' -f1 | tr -d $'\r\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
			value=$(echo "$line" | cut -d ':' -f2- | tr -d $'\r\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
			colon=$(echo "$line" | grep ':')

			echo " .. \n key is $key \t value is $value \n colon is $colon \n "
			
			if [ "$key" ] && [ "$value" ] && [ "$colon" ]
			then
				html=$(template "$html" "$key" "$value")
			fi
			
			if [ "$key" = "posttitle" ]
				then
					all_posts_excerpts+="<div class=\"post\"><h1 class=\"post-title\">""$value""</h1><hr/>"
			fi
			
			if [ "$key" = "excerpt" ]
				then
					all_posts_excerpts+="<span class=\"post-date\">""$value"" </span>"
			fi
		done < <(echo "$metadata")
		
		# html=$(template "$html" content "$post {{content}}" true)
		html=$(template "$html" postcontent "$content")
		
		# this section can be collated from both dir and file level loops to the time of initialisation of html/dir_html
		html=$(template "$html" sitetitle "$site_title")
		html=$(template "$html" sitesubtitle "$site_sub_title")
		html=$(template "$html" sectiontitle "${nav_name[i]}")
		
		# old code for writing html file; now taken inside the inner loop to create a file per post instead of per dir - part 2
		# TODO: below code to identify the html for top level index.html does not work properly. 
		if [ -z "$firsthtml" ]		# -z checks if the arguement is null; it's checking if $firsthtml has been initialised
		then
			firsthtml="$html"
			firstpath="${nav_url[i]}"
		fi

		if [ "${nav_depth[i]}" = 0 ]
		then
			basepath="./"
		else
			basepath=$(yes "../" | head -n ${nav_depth[i]} | tr -d '\n')
		fi

		html=$(template "$html" basepath "$basepath")
		html=$(template "$html" disqus_identifier "${nav_url[i]}")

		# set default values for {{XXX:default}} strings
		html=$(echo "$html" | sed "s/{{[^{}]*:\([^}]*\)}}/\1/g")

		# remove references to any unused {{xxx}} template variables and empty <ul>s from navigation
		html=$(echo "$html" | sed "s/{{[^}]*}}//g; s/<ul><\/ul>//g")

		# echo "$html" > "$topdir/_site/${nav_url[i]}"/index.html
		echo "$html" > "$topdir/_site/${nav_url[i]}/$filename".html
		
		# add MORE link for each post excerpt for directory level html
		all_posts_excerpts+="<a href=./$filename"".html> More </a> <br/>"

		((section_index++))
		((j++))
	done
	
	# generate directory level html with list of all posts ==============================
	dir_html=$(template "$dir_html" all_posts_excerpts "$all_posts_excerpts")
	# this section can be collated from both dir and file level loops to the time of initialisation of html/dir_html
	dir_html=$(template "$dir_html" sitetitle "$site_title")
	dir_html=$(template "$dir_html" sitesubtitle "$site_sub_title")
	dir_html=$(template "$dir_html" sectiontitle "${nav_name[i]}")
	
	if [ "${nav_depth[i]}" = 0 ]
		then
			basepath="./"
		else
			basepath=$(yes "../" | head -n ${nav_depth[i]} | tr -d '\n')
	fi

	dir_html=$(template "$dir_html" basepath "$basepath")
	
	# set default values for {{XXX:default}} strings
	dir_html=$(echo "$dir_html" | sed "s/{{[^{}]*:\([^}]*\)}}/\1/g")

	# remove references to any unused {{xxx}} template variables and empty <ul>s from navigation
	dir_html=$(echo "$dir_html" | sed "s/{{[^}]*}}//g; s/<ul><\/ul>//g")

	echo "$dir_html" > "$topdir/_site/${nav_url[i]}/"index.html
	# echo "$dir_html" > "${paths[i]}"index.html
	
done



# write top level index.html =========================================================

basepath="./"
firsthtml=$(template "$firsthtml" basepath "$basepath")
firsthtml=$(template "$firsthtml" disqus_identifier "$firstpath")
firsthtml=$(template "$firsthtml" resourcepath "$firstpath/")
firsthtml=$(echo "$firsthtml" | sed "s/{{[^{}]*:\([^}]*\)}}/\1/g")
firsthtml=$(echo "$firsthtml" | sed "s/{{[^}]*}}//g; s/<ul><\/ul>//g")
echo "$firsthtml" > "$topdir/_site"/index.html

printf "\nStarting encode\n"

# copy resources to _site
echo "topdir is: $topdir \n"
echo "scriptdir/theme_dir is: $scriptdir/$theme_dir/"
rsync -av --exclude="template.html" --exclude="post-template.html" "$scriptdir/$theme_dir/" "$topdir/_site/" >/dev/null

cleanup
