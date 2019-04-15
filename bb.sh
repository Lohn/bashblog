#!/usr/bin/env bash

# BashBlog, a simple blog system written in a single bash script
# (C) Carlos Fenollosa <carlos.fenollosa@gmail.com>, 2011-2016 and contributors
# https://github.com/carlesfe/bashblog/contributors
# Check out README.md for more details

# Global variables
# It is recommended to perform a 'rebuild' after changing any of this in the code

# Config file. Any settings "key=value" written there will override the
# global_variables defaults. Useful to avoid editing bb.sh and having to deal
# with merges in VCS
global_config="config/.config"

# This function will load all the variables defined here. They might be overridden
# by the 'global_config' file contents
global_variables() {

    # Markdown location. Trying to autodetect by default.
    # The invocation must support the signature 'markdown_bin in.md > out.php'
    if which hsmarkdown 2>/dev/null; then
      
      markdown_bin=$(which hsmarkdown 2>/dev/null)
        
    elif [[ -f Markdown.pl ]]; then
      
      markdown_bin=./Markdown.pl || markdown_bin=$(which Markdown.pl 2>/dev/null || which markdown 2>/dev/null)
    
    elif [[ -f markdown_py ]]; then
      
      markdown_bin=./markdown_py || markdown_bin=$(which Markdown_py 2>/dev/null)
      
    else
      
      markdown_bin=./md2html.awk
    
    fi
}

# Check for the validity of some variables
# DO NOT EDIT THIS FUNCTION unless you know what you're doing
global_variables_check() {
    [[ $header_file == .header.php ]] &&
        echo "Please check your configuration. '.header.php' is not a valid value for the setting 'header_file'" &&
        exit
    [[ $footer_file == .footer.php ]] &&
        echo "Please check your configuration. '.footer.php' is not a valid value for the setting 'footer_file'" &&
        exit
}


# Test if the markdown script is working correctly
test_markdown() {
    [[ -n $markdown_bin ]] &&
        (
        [[ $("$markdown_bin" <<< $'line 1\n\nline 2') == $'<p>line 1</p>\n\n<p>line 2</p>' ]] ||
        [[ $("$markdown_bin" <<< $'line 1\n\nline 2') == $'<p>line 1</p>\n<p>line 2</p>' ]]
        )
}


# Parse a Markdown file into HTML and return the generated file
markdown() {
    out=${1%.md}.php
    while [[ -f $out ]]; do out=${out%.php}.$RANDOM.php; done
    $markdown_bin "$1" > "$out"
    echo "$out"
}


# Prints the required google analytics code
google_analytics() {
    [[ -z $global_analytics && -z $global_analytics_file ]]  && return

    if [[ -z $global_analytics_file ]]; then
        echo "<script type=\"text/javascript\">

        var _gaq = _gaq || [];
        _gaq.push(['_setAccount', '${global_analytics}']);
        _gaq.push(['_trackPageview']);

        (function() {
        var ga = document.createElement('script'); ga.type = 'text/javascript'; ga.async = true;
        ga.src = ('https:' == document.location.protocol ? 'https://ssl' : 'http://www') + '.google-analytics.com/ga.js';
        var s = document.getElementsByTagName('script')[0]; s.parentNode.insertBefore(ga, s);
        })();

        </script>"
    else
        cat "$global_analytics_file"
    fi
}

# Prints the required code for hashover comments
hashover_body() {
  if [[ $hashover_body = "on" ]]; then

    echo '<script>
        var rows="'$hashover_rows'";        // Sets "Comments" field height
        var name_on="'$hashover_name_on'";    // Disables "Name" field
        var passwd_on="'$hashover_passwd_on'";  // Disables "Password" field
        var email_on="'$hashover_email_on'";   // Disables "E-mail" field
        var sites_on="'$hashover_sites_on'";   // Disables "Website" field
</script>
<div id="hashover"></div>
<script src="hashover-next/comments.php"></script>
<noscript>You must have JavaScript enabled to use the comments.</noscript>'
fi
}

# Prints the required code for hashover in the footer
hashover_footer() {
  if [[ $hashover_footer = "on"  ]]; then
    echo '<script>
    var rows="'$hashover_rows'";        // Sets "Comments" field height
    var name_on="'$hashover_name_on'";    // Disables "Name" field
    var passwd_on="'$hashover_passwd_on'";  // Disables "Password" field
    var email_on="'$hashover_email_on'";   // Disables "E-mail" field
    var sites_on="'$hashover_sites_on'";   // Disables "Website" field
</script>
<div id="hashover"></div>
<script src="hashover-next/comments.php"></script>
<noscript>You must have JavaScript enabled to use the comments.</noscript>'
fi
}

# Reads HTML file from stdin, prints its content to stdout
# $1    where to start ("text" or "entry")
# $2    where to stop ("text" or "entry")
# $3    "cut" to remove text from <hr /> to <!-- text end -->
#       note that this does not remove <hr /> line itself,
#       so you can see if text was cut or not
get_html_file_content() {
    awk "/<!-- $1 begin -->/, /<!-- $2 end -->/{
        if (!/<!-- $1 begin -->/ && !/<!-- $2 end -->/) print
        if (\"$3\" == \"cut\" && /$cut_line/){
            if (\"$2\" == \"text\") exit # no need to read further
            while (getline > 0 && !/<!-- text end -->/) {
                if (\"$cut_tags\" == \"no\" && /^<p>$template_tags_line_header/ ) print 
            }
        }
    }"
}

# Edit an existing, published .php file while keeping its original timestamp
# Please note that this function does not automatically republish anything, as
# it is usually called from 'main'.
#
# Note that it edits HTML file, even if you wrote the post as markdown originally
# Note that if you edit title then filename might also change
#
# $1 	the file to edit
# $2	(optional) edit mode:
#	"keep" to keep old filename
#	"full" to edit full HTML, and not only text part (keeps old filename)
#	leave empty for default behavior (edit only text part and change name)
edit() {
    [[ ! -f "${1%%.*}.php" ]] && echo "Can't edit post "${1%%.*}.php", did you mean to use \"bb.sh post <draft_file>\"?" && exit -1
    # Original post timestamp
    edit_timestamp=$(LC_ALL=C date -r "${1%%.*}.php" +"$date_format_full" )
    touch_timestamp=$(LC_ALL=C date -r "${1%%.*}.php" +"$date_format_timestamp")
    tags_before=$(tags_in_post "${1%%.*}.php")
    if [[ $2 == full ]]; then
        $EDITOR "$1"
        filename=$1
    else
        if [[ ${1##*.} == md ]]; then
            test_markdown
            if (($? != 0)); then
                echo "Markdown is not working, please edit HTML file directly."
                exit
            fi
            # editing markdown file
            $EDITOR "$1"
            TMPFILE=$(markdown "$1")
            filename=${1%%.*}.php
        else
            # Create the content file
            TMPFILE=$(basename "$1").$RANDOM.php
            # Title
            get_post_title "$1" > "$TMPFILE"
            # Post text with plaintext tags
            get_html_file_content 'text' 'text' <"$1" | sed "/^<p>$template_tags_line_header/s|<a href='$prefix_tags\([^']*\).php'>\\1</a>|\\1|g" >> "$TMPFILE"
            $EDITOR "$TMPFILE"
            filename=$1
        fi
        rm "$filename"
        if [[ $2 == keep ]]; then
            parse_file "$TMPFILE" "$edit_timestamp" "$filename"
        else
            parse_file "$TMPFILE" "$edit_timestamp" # this command sets $filename as the html processed file
            [[ ${1##*.} == md ]] && mv "$1" "${filename%%.*}.md" 2>/dev/null
        fi
        rm "$TMPFILE"
    fi
    touch -t "$touch_timestamp" "$filename"
    touch -t "$touch_timestamp" "$1"
    chmod 644 "$filename"
    echo "Posted $filename"
    tags_after=$(tags_in_post "$filename")
    relevant_tags=$(echo "$tags_before $tags_after" | tr ',' ' ' | tr ' ' '\n' | sort -u | tr '\n' ' ')
    if [[ ! -z $relevant_tags ]]; then
        relevant_posts="$(posts_with_tags $relevant_tags) $filename"
        rebuild_tags "$relevant_posts" "$relevant_tags"
    fi
}

# Create a Twitter summary (twitter "card") for the post
#
# $1 the post file
# $2 the title
twitter_card() {
    [[ -z $global_twitter_username ]] && return
    
    echo "<meta name='twitter:card' content='summary' />"
    echo "<meta name='twitter:site' content='@$global_twitter_username' />"
    echo "<meta name='twitter:title' content='$2' />" # Twitter truncates at 70 char
    description=$(grep -v "^<p>$template_tags_line_header" "$1" | sed -e 's/<[^>]*>//g' | head -c 250 | tr '\n' ' ' | sed "s/\"/'/g") 
    echo "<meta name='twitter:description' content=\"$description\" />"
    image=$(sed -n 's/.*<img.*src="\([^"]*\)".*/\1/p' "$1" | head -n 1) # First image is fine
    [[ -z $image ]] && return
    [[ $image =~ ^https?:// ]] || image=$global_url/$image # Check that URL is absolute
    echo "<meta name='twitter:image' content='$image' />"
}

Sharingbuttons() {
  [[ -n $Sharingbuttons_template ]] && source $Sharingbuttons_template
}
# Check if the file is a 'boilerplate' (i.e. not a post)
# The return values are designed to be used like this inside a loop:
# is_boilerplate_file <file> && continue
#
# $1 the file
#
# Return 0 (bash return value 'true') if the input file is an index, feed, etc
# or 1 (bash return value 'false') if it is a blogpost
is_boilerplate_file() {
    name=${1#./}
    # First check against user-defined non-blogpost pages
    for item in "${non_blogpost_files[@]}"; do
        [[ "$name" == "$item" ]] && return 0
    done

    case $name in
    ( "$index_file" | "$archive_index" | "$tags_index" | "$footer_file" | "$header_file" | "$global_analytics_file" | "$prefix_tags"* )
        return 0 ;;
    ( * ) # Check for excluded
        for excl in "${html_exclude[@]}"; do
            [[ $name == "$excl" ]] && return 0
        done
        return 1 ;;
    esac
}

# Adds all the bells and whistles to format the html page
# Every blog post is marked with a <!-- entry begin --> and <!-- entry end -->
# which is parsed afterwards in the other functions. There is also a marker
# <!-- text begin --> to determine just the beginning of the text body of the post
#
# $1     a file with the body of the content
# $2     the output file
# $3     "yes" if we want to generate the index.php,
#        "no" to insert new blog posts
# $4     title for the html header
# $5     original blog timestamp
# $6     post author
create_html_page() {
    content=$1
    filename=$2
    index=$3
    title=$4
    timestamp=$5
    author=$6

    # Create the actual blog post
    # html, head
    {
        cat ".header.php"
        echo "<title>$title</title>"
        google_analytics
        twitter_card "$content" "$title"
        echo "</head>"
        echo "<body>"
        # stuff to add before the actual body content
        [[ -n $body_begin_file ]] && cat "$body_begin_file"
        # body divs
        echo '<div class="container">'
        echo '<div class="blog-header">'
        # echo '<div class="header">'
        # blog title
        echo '<div class="jumbotron">'
        # echo '<h1 class="blog-title">'
        echo '<span class="pull-right">'
        echo '<a href="/"><img src="public/img/bash.png" alt="'$title' - '$global_description'" class="toplogo"></a>'        
        echo '</span>'
        cat .title.php
        # echo '</h1>' # title
        echo '</div>' # Jumbotron
        echo '</div>' # header
        #echo '</div>' # headerholder
        echo '<div class="row">'
        echo '<div class="col-sm-8 blog-main">' # content

        file_url=${filename#./}
        file_url=${file_url%.rebuilt} # Get the correct URL when rebuilding
        # one blog entry
        if [[ $index == no ]]; then
            echo '<!-- entry begin -->' # marks the beginning of the whole post
            echo "<h2 class=\"blog-post-title\"><a href=\"$file_url\">"
            # remove possible <p>'s on the title because of markdown conversion
            title=${title//<p>/}
            title=${title//<\/p>/}
            echo "$title"
            echo '</a></h2>'
            if [[ -z $timestamp ]]; then
                echo "<!-- $date_inpost: #$(LC_ALL=$date_locale date +"$date_format_timestamp")# -->"
            else
                echo "<!-- $date_inpost: #$(LC_ALL=$date_locale date +"$date_format_timestamp" --date="$timestamp")# -->"
            fi
            if [[ -z $timestamp ]]; then
                echo -n "<p class=\"blog-post-meta\">$(LC_ALL=$date_locale date +"$date_format")"
            else
                echo -n "<p class=\"blog-post-meta\">$(LC_ALL=$date_locale date +"$date_format" --date="$timestamp")"
            fi
            [[ -n $author ]] && echo -e " &mdash; \n$author"
            echo "</p>"
            echo '<!-- text begin -->' # This marks the text body, after the title, date...
        fi
        cat "$content" # blog-main
        if [[ $index == no ]]; then
            echo -e '\n<!-- text end -->'

            # twitter "$global_url/$file_url"
            Sharingbuttons "$global_url/$file_url"

            echo '<!-- entry end -->' # absolute end of the blog-post
        fi

        echo '</div>' # end blog-main

        [[ -n $content_file ]] && cat "$content_file" # Add content after blog-main, such as sidebar content

        # Add hashover commments except for index and all_posts pages
        [[ $index == no ]] && hashover_body

        # close divs
        echo '</div>' # row
        echo '</div>' # container 
        # page footer
        cat .footer.php
        hashover_footer
        [[ -n $body_end_file ]] && cat "$body_end_file"
        echo '</body>'
        echo '</html>'
    } > "$filename"
}

# Parse the plain text file into an html file
#
# $1    source file name
# $2    (optional) timestamp for the file
# $3    (optional) destination file name
# note that although timestamp is optional, something must be provided at its
# place if destination file name is provided, i.e:
# parse_file source.txt "" destination.php
parse_file() {
    # Read for the title and check that the filename is ok
    title=""
    while IFS='' read -r line; do
        if [[ -z $title ]]; then
            # remove extra <p> and </p> added by markdown
            title=$(echo "$line" | sed 's/<\/*p>//g')
            if [[ -n $3 ]]; then
                filename=$3
            else
                filename=$title
                [[ -n $convert_filename ]] &&
                    filename=$(echo "$title" | eval "$convert_filename")
                [[ -n $filename ]] || 
                    filename=$RANDOM # don't allow empty filenames

                filename=$filename.php

                # Check for duplicate file names
                while [[ -f $filename ]]; do
                    filename=${filename%.php}$RANDOM.php
                done
            fi
            content=$filename.tmp
        # Parse possible tags
        elif [[ $line == "<p>$template_tags_line_header"* ]]; then
            tags=$(echo "$line" | cut -d ":" -f 2- | sed -e 's/<\/p>//g' -e 's/^ *//' -e 's/ *$//' -e 's/, /,/g')
            IFS=, read -r -a array <<< "$tags"

            echo -n "<p>$template_tags_line_header " >> "$content"
            for item in "${array[@]}"; do
                echo -n "<a href='$prefix_tags$item.php'>$item</a>, "
            done | sed 's/, $/<\/p>/g' >> "$content"
        else
            echo "$line" >> "$content"
        fi
    done < "$1"

    # Create the actual html page
    create_html_page "$content" "$filename" no "$title" "$2" "$global_author"
    rm "$content"
}

# Manages the creation of the text file and the parsing to html file
# also the drafts
write_entry() {
    test_markdown && fmt=md || fmt=html
    f=$2
    [[ $2 == -html ]] && fmt=html && f=$3

    if [[ -n $f ]]; then
        TMPFILE=$f
        if [[ ! -f $TMPFILE ]]; then
            echo "The file doesn't exist"
            delete_includes
            exit
        fi
        # guess format from TMPFILE
        extension=${TMPFILE##*.}
        [[ $extension == md || $extension == html ]] && fmt=$extension
        # but let user override it (`bb.sh post -html file.md`)
        [[ $2 == -html ]] && fmt=html
        # Test if Markdown is working before re-posting a .md file
        if [[ $extension == md ]]; then
            test_markdown
            if (($? != 0)); then
                echo "Markdown is not working, please edit HTML file directly."
                exit
            fi
        fi
    else
        TMPFILE=.entry-$RANDOM.$fmt
        echo -e "Title on this line\n" >> "$TMPFILE"

        [[ $fmt == html ]] && cat << EOF >> "$TMPFILE"
<p>The rest of the text file is an <b>html</b> blog post. The process will continue as soon
as you exit your editor.</p>

<p>$template_tags_line_header $default_tags</p>
EOF
        [[ $fmt == md ]] && cat << EOF >> "$TMPFILE"
The rest of the text file is a **Markdown** blog post. The process will continue
as soon as you exit your editor.

$template_tags_line_header $default_tags
EOF
    fi
    chmod 600 "$TMPFILE"

    post_status="E"
    filename=""
    while [[ $post_status != "p" && $post_status != "P" ]]; do
        [[ -n $filename ]] && rm "$filename" # Delete the generated html file, if any
        $EDITOR "$TMPFILE"
        if [[ $fmt == md ]]; then
            html_from_md=$(markdown "$TMPFILE")
            parse_file "$html_from_md"
            rm "$html_from_md"
        else
            parse_file "$TMPFILE" # this command sets $filename as the html processed file
        fi

        chmod 644 "$filename"
        [[ -n $preview_url ]] || preview_url=$global_url
        echo "To preview the entry, open $preview_url/$filename in your browser"

        echo -n "[A]bort, [P]ost this entry, [E]dit again, [D]raft for later? (A/p/E/d) "
        read -r post_status
        if [[ $post_status == d || $post_status == D ]]; then
            mkdir -p "drafts/"
            chmod 700 "drafts/"

            title=$(head -n 1 $TMPFILE)
            [[ -n $convert_filename ]] && title=$(echo "$title" | eval "$convert_filename")
            [[ -n $title ]] || title=$RANDOM

            draft=drafts/$title.$fmt
            mv "$TMPFILE" "$draft"
            chmod 600 "$draft"
            rm "$filename"
            delete_includes
            echo "Saved your draft as '$draft'"
            exit
        fi
        if [[ $post_status == a || $post_status == A ]]; then
          [[ -n $filename ]] && rm "$filename" # Delete the generated html file, if any
            delete_includes
            if [[ $fmt == md ]]; then
              rm "$TMPFILE"
            fi
            echo "Deleted the generated html file '$filename'"
            exit
        fi
    done

    if [[ $fmt == md && -n $save_markdown ]]; then
        mv "$TMPFILE" "${filename%%.*}.md"
    else
        rm "$TMPFILE"
    fi
    chmod 644 "$filename"
    echo "Posted $filename"
    relevant_tags=$(tags_in_post $filename)
    if [[ -n $relevant_tags ]]; then
        relevant_posts="$(posts_with_tags $relevant_tags) $filename"
        rebuild_tags "$relevant_posts" "$relevant_tags"
    fi
}

# Create an index page with all the posts
all_posts() {
    echo -n "Creating an index page with all the posts "
    contentfile=$archive_index.$RANDOM
    while [[ -f $contentfile ]]; do
        contentfile=$archive_index.$RANDOM
    done

    {
        echo "<h3>$template_archive_title</h3>"
        prev_month=""
        while IFS='' read -r i; do
            is_boilerplate_file "$i" && continue
            echo -n "." 1>&3
            # Month headers
            month=$(LC_ALL=$date_locale date -r "$i" +"$date_allposts_header")
            if [[ $month != "$prev_month" ]]; then
                [[ -n $prev_month ]] && echo "</ul>"  # Don't close ul before first header
                echo "<h4 class='allposts_header'>$month</h4>"
                echo "<ul>"
                prev_month=$month
            fi
            # Title
            title=$(get_post_title "$i")
            echo -n "<li><a href=\"$i\">$title</a> &mdash;"
            # Date
            date=$(LC_ALL=$date_locale date -r "$i" +"$date_format")
            echo " $date</li>"
        done < <(ls -t ./*.php)
        echo "" 1>&3
        echo "</ul>"
        echo "<div id=\"all_posts\"><a href=\"./$index_file\">$template_archive_index_page</a></div>"
    } 3>&1 >"$contentfile"

    create_html_page "$contentfile" "$archive_index.tmp" yes "$global_title &mdash; $template_archive_title" "$global_author"
    mv "$archive_index.tmp" "$archive_index"
    chmod 644 "$archive_index"
    rm "$contentfile"
}

# Create an index page with all the tags
all_tags() {
    echo -n "Creating an index page with all the tags "
    contentfile=$tags_index.$RANDOM
    while [[ -f $contentfile ]]; do
        contentfile=$tags_index.$RANDOM
    done

    {
        echo "<h3>$template_tags_title</h3>"
        echo "<ul>"
        for i in $prefix_tags*.php; do
            [[ -f "$i" ]] || break
            echo -n "." 1>&3
            nposts=$(grep -c "<\!-- text begin -->" "$i")
            tagname=${i#"$prefix_tags"}
            tagname=${tagname%.php}
            case $nposts in
                1) word=$template_tags_posts_singular;;
                2|3|4) word=$template_tags_posts_2_4;;
                *) word=$template_tags_posts;;
            esac
            echo "<li><a href=\"$i\">$tagname</a> &mdash; $nposts $word</li>"
        done
        echo "" 1>&3
        echo "</ul>"
        echo "<div id=\"all_posts\"><a href=\"./$index_file\">$template_archive_index_page</a></div>"
    } 3>&1 > "$contentfile"

    create_html_page "$contentfile" "$tags_index.tmp" yes "$global_title &mdash; $template_tags_title" "$global_author"
    mv "$tags_index.tmp" "$tags_index"
    chmod 644 "$tags_index"
    rm "$contentfile"
}

# Generate the index.php with the content of the latest posts
rebuild_index() {
    echo -n "Rebuilding the index "
    newindexfile=$index_file.$RANDOM
    contentfile=$newindexfile.content
    while [[ -f $newindexfile ]]; do 
        newindexfile=$index_file.$RANDOM
        contentfile=$newindexfile.content
    done

    # Create the content file
    {
        n=0
        while IFS='' read -r i; do
            is_boilerplate_file "$i" && continue;
            if ((n >= number_of_index_articles)); then break; fi
            if [[ -n $cut_do ]]; then
                get_html_file_content 'entry' 'entry' 'cut' <"$i" | awk "/$cut_line/ { print \"<p class=\\\"readmore\\\"><a href=\\\"$i\\\">$template_read_more</a></p>\" ; next } 1"
            else
                get_html_file_content 'entry' 'entry' <"$i"
            fi
            echo -n "." 1>&3
            n=$(( n + 1 ))
        done < <(ls -t ./*.php) # sort by date, newest first

        feed=$blog_feed
        if [[ -n $global_feedburner ]]; then feed=$global_feedburner; fi
        echo "<div id=\"all_posts\"><a href=\"$archive_index\">$template_archive</a> &mdash; <a href=\"$tags_index\">$template_tags_title</a> &mdash; <a href=\"$feed\">$template_subscribe</a></div>"
    } 3>&1 >"$contentfile"

    echo ""

    create_html_page "$contentfile" "$newindexfile" yes "$global_title" "$global_author"
    rm "$contentfile"
    mv "$newindexfile" "$index_file"
    chmod 644 "$index_file"
}

# Finds all tags referenced in one post.
# Accepts either filename as first argument, or post content at stdin
# Prints one line with space-separated tags to stdout
tags_in_post() {
    sed -n "/^<p>$template_tags_line_header/{s/^<p>$template_tags_line_header//;s/<[^>]*>//g;s/[ ,]\+/ /g;p;}" "$1" | tr ', ' ' '
}

# Finds all posts referenced in a number of tags.
# Arguments are tags
# Prints one line with space-separated tags to stdout
posts_with_tags() {
    (($# < 1)) && return
    set -- "${@/#/$prefix_tags}"
    set -- "${@/%/.php}"
    sed -n '/^<h2 class="blog-post-title"><a href="[^"]*">/{s/.*href="\([^"]*\)">.*/\1/;p;}' "$@" 2> /dev/null
}

# Rebuilds tag_*.php files
# if no arguments given, rebuilds all of them
# if arguments given, they should have this format:
# "FILE1 [FILE2 [...]]" "TAG1 [TAG2 [...]]"
# where FILEn are files with posts which should be used for rebuilding tags,
# and TAGn are names of tags which should be rebuilt.
# example:
# rebuild_tags "one_post.php another_article.php" "example-tag another-tag"
# mind the quotes!
rebuild_tags() {
    if (($# < 2)); then
        # will process all files and tags
        files=$(ls -t ./*.php)
        all_tags=yes
    else
        # will process only given files and tags
        files=$(printf '%s\n' $1 | sort -u)
        files=$(ls -t $files)
        tags=$2
    fi
    echo -n "Rebuilding tag pages "
    n=0
    if [[ -n $all_tags ]]; then
        rm ./"$prefix_tags"*.php &> /dev/null
    else
        for i in $tags; do
            rm "./$prefix_tags$i.php" &> /dev/null
        done
    fi
    # First we will process all files and create temporal tag files
    # with just the content of the posts
    tmpfile=tmp.$RANDOM
    while [[ -f $tmpfile ]]; do tmpfile=tmp.$RANDOM; done
    while IFS='' read -r i; do
        is_boilerplate_file "$i" && continue;
        echo -n "."
        if [[ -n $cut_do ]]; then
            get_html_file_content 'entry' 'entry' 'cut' <"$i" | awk "/$cut_line/ { print \"<p class=\\\"readmore\\\"><a href=\\\"$i\\\">$template_read_more</a></p>\" ; next } 1"
        else
            get_html_file_content 'entry' 'entry' <"$i"
        fi >"$tmpfile"
        for tag in $(tags_in_post "$i"); do
            if [[ -n $all_tags || " $tags " == *" $tag "* ]]; then
                cat "$tmpfile" >> "$prefix_tags$tag".tmp.php
            fi
        done
    done <<< "$files"
    rm "$tmpfile"
    # Now generate the tag files with headers, footers, etc
    while IFS='' read -r i; do
        tagname=${i#./"$prefix_tags"}
        tagname=${tagname%.tmp.php}
        create_html_page "$i" "$prefix_tags$tagname.php" yes "$global_title &mdash; $template_tag_title \"$tagname\"" "$global_author"
        rm "$i"
    done < <(ls -t ./"$prefix_tags"*.tmp.php 2>/dev/null)
    echo
}

# Return the post title
#
# $1 the html file
get_post_title() {
    awk '/<h2 class="blog-post-title"><a href=".+">/, /<\/a><\/h2>/{if (!/<h2 class="blog-post-title"><a href=".+">/ && !/<\/a><\/h2>/) print}' "$1"
}

# Return the post author
#
# $1 the html file
get_post_author() { 
    awk '/<p class="blog-post-meta">.+/, /<!-- text begin -->/{if (!/<p class="blog-post-meta">.+/ && !/<!-- text begin -->/) print}' "$1" | sed 's/<\/p>//g'
}

# Displays a list of the tags
#
# $2 if "-n", tags will be sorted by number of posts
list_tags() {
    if [[ $2 == -n ]]; then do_sort=1; else do_sort=0; fi

    ls ./$prefix_tags*.php &> /dev/null
    (($? != 0)) && echo "No posts yet. Use 'bb.sh post' to create one" && return

    lines=""
    for i in $prefix_tags*.php; do
        [[ -f "$i" ]] || break
        nposts=$(grep -c "<\!-- text begin -->" "$i")
        tagname=${i#"$prefix_tags"}
        tagname=${tagname#.php}
        ((nposts > 1)) && word=$template_tags_posts || word=$template_tags_posts_singular
        line="$tagname # $nposts # $word"
        lines+=$line\\n
    done

    if (( do_sort == 1 )); then
        echo -e "$lines" | column -t -s "#" | sort -nrk 2
    else
        echo -e "$lines" | column -t -s "#" 
    fi
}

# Displays a list of the posts
list_posts() {
    ls ./*.php &> /dev/null
    (($? != 0)) && echo "No posts yet. Use 'bb.sh post' to create one" && return

    lines=""
    n=1
    while IFS='' read -r i; do
        is_boilerplate_file "$i" && continue
        line="$n # $(get_post_title "$i") # $(LC_ALL=$date_locale date -r "$i" +"$date_format")"
        lines+=$line\\n
        n=$(( n + 1 ))
    done < <(ls -t ./*.php)

    echo -e "$lines" | column -t -s "#"
}

# Generate the feed file
make_rss() {
    echo -n "Making RSS "

    rssfile=$blog_feed.$RANDOM
    while [[ -f $rssfile ]]; do rssfile=$blog_feed.$RANDOM; done

    {
        pubdate=$(LC_ALL=C date +"$date_format_full")
        echo '<?xml version="1.0" encoding="UTF-8" ?>' 
        echo '<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:dc="http://purl.org/dc/elements/1.1/">'
        echo "<channel><title>$global_title</title><link>$global_url/$index_file</link>"
        echo "<description>$global_description</description><language>en</language>"
        echo "<lastBuildDate>$pubdate</lastBuildDate>"
        echo "<pubDate>$pubdate</pubDate>"
        echo "<atom:link href=\"$global_url/$blog_feed\" rel=\"self\" type=\"application/rss+xml\" />"
    
        n=0
        while IFS='' read -r i; do
            is_boilerplate_file "$i" && continue
            ((n >= number_of_feed_articles)) && break # max 10 items
            echo -n "." 1>&3
            echo '<item><title>' 
            get_post_title "$i"
            echo '</title><description><![CDATA[' 
            get_html_file_content 'text' 'entry' $cut_do <"$i"
            echo "]]></description><link>$global_url/${i#./}</link>" 
            echo "<guid>$global_url/$i</guid>" 
            echo "<dc:creator>$(get_post_author "$i")</dc:creator>" 
            echo "<pubDate>$(LC_ALL=C date -r "$i" +"$date_format_full")</pubDate></item>"
    
            n=$(( n + 1 ))
        done < <(ls -t ./*.php)
    
        echo '</channel></rss>'
    } 3>&1 >"$rssfile"
    echo ""

    mv "$rssfile" "$blog_feed"
    chmod 644 "$blog_feed"
}

# generate headers, footers, etc
create_includes() {
    {
        echo "<h1 class=\"blog-title\"><a href=\"$global_url/$index_file\">$global_title</a></h1>" 
        echo "<p class=\"lead blog-description\">$global_description</p>"
    } > ".title.php"

    if [[ -f $header_file ]]; then cp "$header_file" .header.php
    else {
        echo '<!DOCTYPE html>'
        echo '<html lang="en"><head>'
        echo '<meta http-equiv="Content-type" content="text/html;charset=UTF-8" />'
        echo '<meta name="viewport" content="width=device-width, initial-scale=1">'
        printf '<link rel="stylesheet" href="%s" type="text/css" />\n' "${css_include[@]}"
        if [[ -z $global_feedburner ]]; then
            echo "<link rel=\"alternate\" type=\"application/rss+xml\" title=\"$template_subscribe_browser_button\" href=\"$blog_feed\" />"
        else 
            echo "<link rel=\"alternate\" type=\"application/rss+xml\" title=\"$template_subscribe_browser_button\" href=\"$global_feedburner\" />"
        fi
        } > ".header.php"
    fi

    if [[ -f $footer_file ]]; then cp "$footer_file" .footer.php
    else {
        protected_mail=${global_email//@/&#64;}
        protected_mail=${protected_mail//./&#46;}
        echo "<footer class=\"footer\">"
        echo "<div class=\"container\">"
        echo "$global_license <a href=\"$global_author_url\">$global_author</a> &mdash; <a href=\"mailto:$protected_mail\">$protected_mail</a><br/>"
        echo 'Generated with <a href="https://github.com/cfenollosa/bashblog">bashblog</a>, a single bash script to easily create blogs like this one<br/>'
        echo '<a href="https://github.com/tmiland/bashblog">Forked</a>, heavily modified and <a href="https://bootswatch.com/3/">Bootstrapped</a><br/>'
        if [[ -n $privacy_policy_url ]]; then
          echo "<a href=\"$privacy_policy_url\">Privacy Policy</a>"
        fi
        echo "</div>"
        echo "</footer>"
        } >> ".footer.php"
    fi
}

# Delete the temporarily generated include files
delete_includes() {
    rm ".title.php" ".footer.php" ".header.php"
}

# Regenerates all the single post entries, keeping the post content but modifying
# the title, html structure, etc
rebuild_all_entries() {
    echo -n "Rebuilding all entries "

    for i in ./*.php; do
        is_boilerplate_file "$i" && continue;
        contentfile=.tmp.$RANDOM
        while [[ -f $contentfile ]]; do contentfile=.tmp.$RANDOM; done

        echo -n "."
        # Get the title and entry, and rebuild the html structure from scratch (divs, title, description...)
        title=$(get_post_title "$i")

        get_html_file_content 'text' 'text' <"$i" >> "$contentfile"

        # Read timestamp from post, if present, and sync file timestamp
        timestamp=$(awk '/<!-- '$date_inpost': .+ -->/ { print }' "$i" | cut -d '#' -f 2)
        [[ -n $timestamp ]] && touch -t "$timestamp" "$i"
        # Read timestamp from file in correct format for 'create_html_page'
        timestamp=$(LC_ALL=C date -r "$i" +"$date_format_full")

        create_html_page "$contentfile" "$i.rebuilt" no "$title" "$timestamp" "$(get_post_author "$i")"
        # keep the original timestamp!
        timestamp=$(LC_ALL=C date -r "$i" +"$date_format_timestamp")
        mv "$i.rebuilt" "$i"
        chmod 644 "$i"
        touch -t "$timestamp" "$i"
        rm "$contentfile"
    done
    echo ""
}

# Displays the help
usage() {
    echo "$global_software_name v$global_software_version"
    echo "Usage: $0 command [filename]"
    echo ""
    echo "Commands:"
    echo "    post [-html] [filename] insert a new blog post, or the filename of a draft to continue editing it"
    echo "                            it tries to use markdown by default, and falls back to HTML if it's not available."
    echo "                            use '-html' to override it and edit the post as HTML even when markdown is available"
    echo "    edit [-n|-f] [filename] edit an already published .php or .md file. **NEVER** edit manually a published .php file,"
    echo "                            always use this function as it keeps internal data and rebuilds the blog"
    echo "                            use '-n' to give the file a new name, if title was changed"
    echo "                            use '-f' to edit full html file, instead of just text part (also preserves name)"
    echo "    delete [filename]       deletes the post and rebuilds the blog"
    echo "    rebuild                 regenerates all the pages and posts, preserving the content of the entries"
    echo "    reset                   deletes everything except this script. Use with a lot of caution and back up first!"
    echo "    list                    list all posts"
    echo "    tags [-n]               list all tags in alphabetical order"
    echo "                            use '-n' to sort list by number of posts"
    echo ""
    echo "For more information please open $0 in a code editor and read the header and comments"
}

# Delete all generated content, leaving only this script
reset() {
    echo "Are you sure you want to delete all blog entries? Please write \"Yes, I am!\" "
    read -r line
    if [[ $line == "Yes, I am!" ]]; then
        rm .*.php ./*.php ./*.css ./*.rss &> /dev/null
        echo
        echo "Deleted all posts, stylesheets and feeds."
        echo "Kept your old 'backup/.backup.tar.gz' just in case, please delete it manually if needed."
    else
        echo "Phew! You dodged a bullet there. Nothing was modified."
    fi
}

# Detects if GNU date is installed
date_version_detect() {
	date --version >/dev/null 2>&1
	if (($? != 0));  then
		# date utility is BSD. Test if gdate is installed 
		if gdate --version >/dev/null 2>&1 ; then
            date() {
                gdate "$@"
            }
		else
            # BSD date
            date() {
                if [[ $1 == -r ]]; then
                    # Fall back to using stat for 'date -r'
                    format=${3//+/}
                    stat -f "%Sm" -t "$format" "$2"
                elif [[ $2 == --date* ]]; then
                    # convert between dates using BSD date syntax
                    command date -j -f "$date_format_full" "${2#--date=}" "$1" 
                else
                    # acceptable format for BSD date
                    command date -j "$@"
                fi
            }
        fi
    fi    
}

# Main function
# Encapsulated on its own function for readability purposes
#
# $1     command to run
# $2     file name of a draft to continue editing (optional)
do_main() {
    # Detect if using BSD date or GNU date
    date_version_detect
    # Load default configuration, then override settings with the config file
    global_variables
    [[ -f $global_config ]] && source "$global_config" &> /dev/null 
    global_variables_check

    # Check for $EDITOR
    [[ -z $EDITOR ]] && 
        echo "Please set your \$EDITOR environment variable. For example, to use nano, add the line 'export EDITOR=nano' to your \$HOME/.bashrc file" && exit

    # Check for validity of argument
    [[ $1 != "reset" && $1 != "post" && $1 != "rebuild" && $1 != "list" && $1 != "edit" && $1 != "delete" && $1 != "tags" ]] && 
        usage && exit

    [[ $1 == list ]] &&
        list_posts && exit

    [[ $1 == tags ]] &&
        list_tags "$@" && exit

    if [[ $1 == edit ]]; then
        if (($# < 2)) || [[ ! -f ${!#} ]]; then
            echo "Please enter a valid .md or .php file to edit"
            exit
        fi
    fi

    # Test for existing html files
    if ls ./*.php &> /dev/null; then
        # We're going to back up just in case
        tar -c -z -f "backup/.backup.tar.gz" -- *.php &&
            chmod 600 "backup/.backup.tar.gz"
    elif [[ $1 == rebuild ]]; then
        echo "Can't find any html files, nothing to rebuild"
        exit
    fi

    # Keep first backup of this day containing yesterday's version of the blog
    [[ ! -f backup/.yesterday.tar.gz || $(date -r backup/.yesterday.tar.gz +'%d') != "$(date +'%d')" ]] &&
        cp backup/.backup.tar.gz backup/.yesterday.tar.gz &> /dev/null

    [[ $1 == reset ]] &&
        reset && exit

    create_css
    create_includes
    [[ $1 == post ]] && write_entry "$@"
    [[ $1 == rebuild ]] && rebuild_all_entries && rebuild_tags
    [[ $1 == delete ]] && rm "$2" &> /dev/null && rebuild_tags
    if [[ $1 == edit ]]; then
        if [[ $2 == -n ]]; then
            edit "$3"
        elif [[ $2 == -f ]]; then
            edit "$3" full
        else
            edit "$2" keep
        fi
    fi
    rebuild_index
    all_posts
    all_tags
    make_rss
    delete_includes
}


#
# MAIN
# Do not change anything here. If you want to modify the code, edit do_main()
#
do_main "$@"

# vim: set shiftwidth=4 tabstop=4 expandtab:
