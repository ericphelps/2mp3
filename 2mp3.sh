#!/bin/bash

# Converts an EPUB, HTML or TXT e-book file into a set of MP3 files.

# REQUIREMENTS:
# operon (to add cover art to the MP3) needs the Quodlibet package 
# html2text needs the Html2text package
# pdftotext needs the Poppler-utils package
# ID3 tagging needs at least one of the following ID3 tag editors:
#	MID3V2:
#		mid3v2 needs the Python-mutagen package
#		The mid3v2 program creates newer (more detailed) version 2.4 tags
#	ID3V2:
#		id3v2 needs the Id3v2 package
#		The id3v2 program creates older (more compatible) version 2.3 tags
# TTS needs at least one of the following cloud voice engines:
# 	AMAZON:
#		aws needs the Awscli package 
# 		A free Amazon Web Services account set up per steps 1 & 3 at: 
#		http://docs.aws.amazon.com/polly/latest/dg/getting-started.html
# 	IBM:
# 		A free IBM/BlueMix account set up per the "Start free" link at:
# 		https://www.ibm.com/watson/developercloud/text-to-speech.html
# 		Credentials for the TTS service set up per the directions at:
# 		https://www.ibm.com/watson/developercloud/doc/common/getting-started-credentials.html#getting-credentials-manually
# 		Add the IBM credentials to the environment e.g., by editing "~/.profile" to include (but using real creds!):
# 		export ibm_tts_user=abcd0123-ef45-ab01-cd67-ef23456789ab
# 		export ibm_tts_password=A1bC2dE3fG4h

echo "Checking requirements..."
# Check the mandatory package list
for pkg in Poppler-utils Quodlibet Html2Text Curl Ffmpeg
do
	if [ $( apt-cache search "${pkg}" | grep -i -c "^${pkg} - " ) -eq 0 ]
	then
		echo ""
		echo "ERROR: "
		read -p "Please install the \"$pkg\" package, then re-run this script."
		exit 1
	else
		echo "${pkg} ... installed"
	fi
done

# Make sure there's at least one ID3 tagger
voiceIndex=0
for pkg in Python-mutagen Id3v2 # Order with most desired last
do
	if [ $( apt-cache search "${pkg}" | grep -i -c "^${pkg} - " ) -ne 0 ]
	then
		voiceIndex=1
		id3_package="${pkg}"
	else
		echo "${pkg} ... installed"
	fi
done
if [ ${voiceIndex} -eq 0 ]
then
	echo "Please read the script comments to see how to "
	read -p "install an ID3 tagger, then re-run this script."
	exit 1
fi 

# Make sure there's at least one voice engine.
voiceIndex=0
# Test for Amazon Polly (assume if you have awscli installed, you set up Polly)
if [ $( apt-cache search "Awscli" | grep -i -c "^Awscli - " ) -ne 0 ]
then
	echo "Awscli ... installed"
	# Build 2-D array of voices: Pipe-delimited index, friendly name, voice name, engine name
	voiceArray[$voiceIndex]="${voiceIndex}|Salli (AWS)|Salli|AWS"
	((voiceIndex+=1))
	voiceArray[$voiceIndex]="${voiceIndex}|Joey (AWS)|Joey|AWS"
	((voiceIndex+=1))
	voiceArray[$voiceIndex]="${voiceIndex}|Kendra (AWS)|Kendra|AWS"
	((voiceIndex+=1))
	voiceArray[$voiceIndex]="${voiceIndex}|Joanna (AWS)|Joanna|AWS"
	((voiceIndex+=1))
fi
# Test for IBM/BlueMix Watson voices (assume if environment set, you have IBM)
if [ "$ibm_tts_user" != "x" ] ; then
	echo '$ibm_tts_user'" ... set"
	if [ "$ibm_tts_password" != "x" ] ; then
		echo '$ibm_tts_password'" ... set"
		voiceArray[$voiceIndex]="${voiceIndex}|Michael (IBM)|en-US_MichaelVoice|IBM"
		((voiceIndex+=1))
		voiceArray[$voiceIndex]="${voiceIndex}|Allison (IBM)|en-US_AllisonVoice|IBM"
		((voiceIndex+=1))
		voiceArray[$voiceIndex]="${voiceIndex}|Lisa (IBM)|en-US_LisaVoice|IBM"
		((voiceIndex+=1))
	fi
fi

# Find out if we found a voice
if [ ${voiceIndex} -eq 0 ]
then
	echo ""
	echo "ERROR: "
	echo "Please read the script comments to see how to "
	read -p "install a tts voice, then re-run this script."
	exit 1
else
	# Print the list of voices
	echo ""
	for x in "${voiceArray[@]}"; do
		IFS="|"
			voiceData=(${x})
			echo "${voiceData[0]}: ${voiceData[1]}"
		unset IFS
	done
	echo ""
	read -p "Please enter the number of voice you want to use: " user_selection
	tts_selection=${voiceArray[${user_selection}]}
	IFS="|"
		tts_data=(${tts_selection})

		tts_voice=${tts_data[2]}
		tts_engine=${tts_data[3]}
	unset IFS
	echo "Using TTS engine: " ${tts_engine}
	echo "Using TTS voice: " ${tts_voice}
fi


# Get a file
clear
echo 'Drag an ".epub", ".pdf", ".html", or ".txt" e-book '
echo 'file; drop it in this window, then press Enter.'
read -p "" source_file

# Remove the single quotes around the file name
source_file="${source_file%\'}"
source_file="${source_file#\'}"

# The output folder (for .jpeg, .text and .mp3 files) will be the source folder
output_folder=${source_file%\/*}
# Make a working directory so we can generate intermediate files
temp_folder=$(mktemp -d "/tmp/2mp3-XXXXXX") || { read -p "Can't create temp folder, sorry!"; exit 1; }

# Ask for author and title
echo ""
read -p "Author Name: " id3_author
echo ""
echo "Note: The title will be the file name. Avoid special characters:"
echo -e "*^|#&!$@?\":'/\\<>[]{}"
read -p "Book Title: " id3_title

# What file extension did we get?
file_ext=${source_file##*.}
# Handle things differently if we got EPUB, HTML, or TXT
case $file_ext in
	"epub")
		echo "Extracting HTM/HTML and JPG/JPEG files from the EPUB..."
		# Extract all HTML files from the EPUB into the working directory
		unzip -o -j -d "${temp_folder}" "${source_file}" *.html *.htm > /dev/null 2>&1
		# Extract JPG files into the output folder (and hope one is useful as cover art)
		unzip -o -j -d "${output_folder}" "${source_file}" *.jpg *.jpeg > /dev/null 2>&1
		# The only way I've found to process files in name order is to
		# use normal globbing to fill an array with unsorted file names, 
		# then sort the array.
		declare -a arr
		i=0
		for htmlfile in "${temp_folder}"/*.htm*
		do
			arr[${i}]=$htmlfile
			i=$(( $i + 1 ))
		done
		# Sort the aray by name (by "version number") so they are in chapter order
		IFS=$'\n' arr=($(sort -V <<<"${arr[*]}"))
		unset IFS
		# Process the array elements
		for ((i=0; i<${#arr[@]}; i++))
		do
			htmlfile="${arr[$i]}"
			# Set a long line of 1300 to stop line wrapping inside paragraphs.
			# Remove xml version tag (which html2text leaves in)
			cat "${htmlfile}" | html2text -width 1300 | grep --binary-files=text -F -v "<?xml" >> "${output_folder}"/"${id3_title}".text
			# More than likely, the html files were chapters, so add a blank line.
			echo "">> "${output_folder}"/"${id3_title}".text
		done
		;;
	"html")
		# Convert a single HTML file to TEXT
		echo "Converting from HTML to TEXT..."
		cat "${source_file}" | html2text -width 1300 | grep -F -v "<?xml" >> "${output_folder}"/"${id3_title}".text
		;;
	"pdf")
		# Convert from PDF to TEXT
		echo "Converting from PDF to TEXT..."
		pdftotext -enc ASCII7 -eol unix -nopgbrk "${source_file}" "${output_folder}"/"${id3_title}".text
		;;
	"txt")
		# Just copy the TXT file to TEXT
		cp "${source_file}" "${output_folder}"/"${id3_title}".text
		;;
	*)
		# Oh, no! Unknown file extension!
		read -p "The file you dropped is one I can't handle. Sorry!"
		exit 1
esac

# Try to preserve smart punctuation because the next step will whack it
asciitext=$( cat "${output_folder}"/"${id3_title}".text )
echo "WAIT: Removing smart single quotes (1 of 3)..."
asciitext="${asciitext//\’/\'}"
echo "WAIT: Removing smart single quotes (2 of 3)..."
asciitext="${asciitext//\`/\'}"
echo "WAIT: Removing smart single quotes (3 of 3)..."
asciitext="${asciitext//\‘/\'}"
echo "WAIT: Removing smart double quotes (1 of 2)..."
asciitext="${asciitext//\“/\"}"
echo "WAIT: Removing smart double quotes (2 of 2)..."
asciitext="${asciitext//\”/\"}"
echo "${asciitext}" > "${output_folder}/${id3_title}.text"

# UTF8 breaks things! Convert to ASCII (safe to do if it's already ASCII).
# This step will *remove* any UTF8 character it doesn't recognize. Good riddance!
echo "WAIT: Converting to ASCII..."
cat "${output_folder}/${id3_title}.text" | iconv -c -f UTF8 -t ASCII > "${temp_folder}/${id3_title}.text"
rm "${output_folder}/${id3_title}.text"
mv "${temp_folder}/${id3_title}.text" "${output_folder}/${id3_title}.text"

# Wait for the user to edit the file
clear
echo "Please use this opportunity to make just-in-time edits to:"
echo "\"${output_folder}/${id3_title}.text\""
echo "Hint: Remove any introductory text like the table of contents and"
echo "final text like credits and references."
echo "DO NOT change the file name. Ensure the text file has the above name!"
echo
echo 'For cover art, create or rename a file as:'
echo "\"${output_folder}/cover.jpeg\""
echo
read -p "Save all your changes, then press any key when ready..."

# Delete all the temporary files we left hanging around...
rm "${temp_folder}"/*.*

# Split text into <1400 bytes (1500 is Amazon Polly max. 5000 is IBM Watson max, but that's *after* URL-encoding.)
# The "split" function will add a 4-digit suffix
split -a 4 -C 1400 -d --additional-suffix=.txt "${output_folder}"/"${id3_title}".text "${temp_folder}"/"${id3_title}"" - "

# Do text to speech ####################################################
for textfile in "${temp_folder}"/*.txt
do
	echo ""
    mp3file=$(basename "${textfile}" .txt).mp3
    wavfile=$(basename "${textfile}" .txt).ogg
	text_portion=$( cat "${textfile}" )
    case $tts_engine in
			"AWS")
				# Use AWS Polly to create the MP3
				echo "Using AWS to convert ""${textfile}"
				# Remove double quotes (we'll need to pass it as a string on the command line)
				aws_text="${text_portion//\"/\ }"
				aws polly synthesize-speech --output-format mp3 --sample-rate 16000 --voice-id "${tts_voice}" --text "${aws_text}" "${output_folder}"/"${mp3file}"
				;;
			"IBM")
				# Use IBM Watson to create a WAV, then convert to MP3
				echo "Using IBM to convert ""${textfile}"
				# Process text for IBM (don't mess with the original text)
				ibm_text=${text_portion}
				# URL-escape the text (curl doesn't do a good job)
				ibm_text="${ibm_text//\%/%25}" # Very first step is to escape any percents!
				ibm_text="${ibm_text//$'\n'/%0A}"
				ibm_text="${ibm_text//$'\r'/%0A}"
				ibm_text="${ibm_text//\ /%20}"
				ibm_text="${ibm_text//\!/%21}"
				ibm_text="${ibm_text//\"/%22}"
				ibm_text="${ibm_text//\#/%23}"
				ibm_text="${ibm_text//\$/%24}"
				ibm_text="${ibm_text//\&/%26}"
				ibm_text="${ibm_text//\'/%27}"
				ibm_text="${ibm_text//\(/%28}"
				ibm_text="${ibm_text//\)/%29}"
				ibm_text="${ibm_text//\*/%2A}"
				ibm_text="${ibm_text//\+/%2B}"
				ibm_text="${ibm_text//\,/%2C}"
				ibm_text="${ibm_text//\//%2F}"
				ibm_text="${ibm_text//\:/%3A}"
				ibm_text="${ibm_text//\;/%3B}"
				ibm_text="${ibm_text//\=/%3D}"
				ibm_text="${ibm_text//\?/%3F}"
				ibm_text="${ibm_text//\@/%40}"
				ibm_text="${ibm_text//\[/%5B}"
				ibm_text="${ibm_text//\]/%5D}"
				ibm_text="${ibm_text//\</%60}"
				ibm_text="${ibm_text//\>/%62}"
				# Build the IBM command line
				curl_url="https://stream.watsonplatform.net/text-to-speech/api/v1/synthesize"
				curl_url+="?accept=audio/ogg;codecs=opus"
				curl_url+="&voice=${tts_voice}"
				curl_url+="&text=${ibm_text}"
				curl -X GET -u "$ibm_tts_user":"$ibm_tts_password" --output "${output_folder}"/"${wavfile}" "${curl_url}"
				# Convert the WAV file to an MP3
				ffmpeg -i "${output_folder}"/"${wavfile}" -ar 16000 -ab 16000 -filter highpass=200 "${output_folder}"/"${mp3file}" 2> /dev/null
				rm "${output_folder}"/"${wavfile}"
				;;
			*)
				# Oh, no! Unknown tts engine!
				read -p "Looks like someone messed up the TTS engine tests. Sorry!"
				exit 1
	esac

    rm "${textfile}"
done

# At this point, we're done with the temporary folder
rm -r "${temp_folder}"

# Set ID3V2 information ################################################
# (if you want to look at mp3 id3v2 info, use "ffprobe" or "id3v2 -l"

# First see which program we'll use
case $id3_package in
	"Id3v2")
		id3_command='id3v2'
		;;
	"Python-mutagen")
		id3_command='mid3v2'
		;;
	*)
		# Oh, no! Unknown package!
		read -p "Looks like someone messed up the package list. Sorry!"
		exit 1
esac

# To help sorting tracks by date, we'll create a random start date that we'll 
# increment for each file. The start will be between 1970-01-01 and 2017-01-01.
# ... and yes, I know multiplying random numbers doesn't give you random numbers ...
epoch_time=$(( 86400 + (($RANDOM * $RANDOM * $RANDOM) % 1483171200) ))
# Round the timestamp to the top of the hour
epoch_time=$(( ($epoch_time / 3600) * 3600))

# Get the number of mp3 files
numfiles=$( ls -v -1 "${output_folder}"/*.mp3 | grep -c .mp3 )
echo "Processing ${numfiles} files..."

# Once again, using a sorted array method :( to do things in order 
# Create an array
declare -a arr
# Use normal globbing to fill the array with unsorted file names
i=0
for mp3file in "${output_folder}"/*.mp3
do
	arr[${i}]=$mp3file
	i=$(( $i + 1 ))
done
# Sort the aray by name (by "version number") so they are in track order
IFS=$'\n' arr=($(sort -V <<<"${arr[*]}"))
unset IFS
# Iterate through the array of MP3 names, setting the ID3v2 data
for ((i=0; i<${#arr[@]}; i++))
do
	mp3file="${arr[$i]}"
	# Status!
	echo "$mp3file"
	
    # Artist
    ${id3_command} -a "${id3_author}" "${mp3file}" #TPE1
    ${id3_command} --TOPE "${id3_author}" "${mp3file}"
    ${id3_command} --TEXT "${id3_author}" "${mp3file}"
    ${id3_command} --TOLY "${id3_author}" "${mp3file}"
    
    # Encoded by (supposed to be a person, but I'll use the program).
    # The mixed quotes are too confusing, so append them separately.
    encoded_by="Script: '"
    encoded_by+=$( basename "$0" )
    encoded_by+="'"
    encoded_by+=" TTS Engine: '"
    encoded_by+="${tts_engine}"
    encoded_by+="'"
    encoded_by+=" TTS Voice: '"
    encoded_by+="${tts_voice}"
    encoded_by+="'"
    encoded_by+=" Text Source: '"
    encoded_by+=$( basename "${source_file}" )
    encoded_by+="'"
    ${id3_command} --TENC "${encoded_by}" "${mp3file}"

    # Title
    mp3num=${mp3file##*-} # for file name like "foo bar-0012.mp3", returns " 0012.mp3"
	mp3num=${mp3file##* } # for file name like " 0012.mp3", returns "0012.mp3"
    mp3num=${mp3num%%.*} # for string like "0012.mp3", returns "0012"
    mp3title="${id3_title}"" - ""${mp3num}"
    ${id3_command} -t "${mp3title}" "${mp3file}" #TIT2
    ${id3_command} --TOAL "${mp3title}" "${mp3file}"
    ${id3_command} --TALB "${mp3title}" "${mp3file}"

    # Genre
    ${id3_command} -g "(101)" "${mp3file}" #TCON (101), which is "Speech"
    
    # Track number
    # Remove leading zeros so we don't have octal problems
	mp3num=$((10#${mp3num})) # Forces "0012" to be decimal 12 (not octal's 10!)

    # Our track number is zero-based, but the max is one-based. Add one to the track!
    mp3num=$(( ${mp3num} + 1 ))
    ${id3_command} -T "${mp3num}""/""${numfiles}" "${mp3file}"

    # Time stamps will increment one minute (60 seconds) for each track
	epoch_time=$(( $epoch_time + 60 ))
    #Time stamps are different between id3v2.3 (id3v2) and id3v2.4 (midid3v2)
	case $id3_command in
		"mid3v2")
			# Format the time as a string YYYY-MM-DDThh:mm:ss-hh:mm
			string_time=$(date --date="@${epoch_time}" +%Y-%m-%dT-%H:%M:%S)
			# Use the random (incremented) time for the important stuff
			${id3_command} --TDOR "${string_time}" "${mp3file}" # Original release time
			${id3_command} --TDRC "${string_time}" "${mp3file}" # Recording time
			${id3_command} --TDRL "${string_time}" "${mp3file}" # Release time
			# Use the real time for the unimportant stuff
			string_time=$( date +%Y-%m-%dT-%H:%M:%S )
			${id3_command} --TDTG "${string_time}" "${mp3file}" # Tagging time
			${id3_command} --TDEN "${string_time}" "${mp3file}" # Encoding time
			;;
		"id3v2")
			${id3_command} --TYER $(date --date="@${epoch_time}" +%Y) "${mp3file}" # Year
			${id3_command} --TDAT $(date --date="@${epoch_time}" +%m%d) "${mp3file}" # Month Date
			${id3_command} --TIME $(date --date="@${epoch_time}" +%H%M) "${mp3file}" # Hour Minute
			;;
		*)
			# Oh, no! Unknown program!
			read -p "Looks like someone messed up the id3 command list. Sorry!"
			exit 1
	esac
	
	# Cover art (APIC)
    if [ -f "${output_folder}"/cover.jpeg ] # if "cover.jpeg" exists, add it as cover art
    then
		# operon complains about GdkPixbuf version not being specified. Hide those errors!
        operon image-set "${output_folder}/cover.jpeg" "${mp3file}"> /dev/null 2>&1
    fi
done
