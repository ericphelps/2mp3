#!/bin/bash

# Converts an EPUB, HTML or TXT e-book file into a set of MP3 files.

# REQUIREMENTS:
# html2text needs the html2text package
# pdftotext needs the poppler-utils package
# sox needs the following packages: sox, libsox-fmt-base, libsox-fmt-mp3
# curl needs the curl package
# eyeD3 needs the eyed3 package
# xxd needs the vim-common package
# Text-To-Speech needs at least one of the following cloud voice engines:
# 	AMAZON:
#		aws needs the awscli package and...
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

echo "Requirements Check:"
# Check the mandatory package list
for pkg in poppler-utils eyed3 vim-common html2Text curl sox libsox-fmt-base libsox-fmt-mp3
do
	if [ $( apt-cache search "${pkg}" | grep -i -c "^${pkg} - " ) -eq 0 ]
	then
		echo ""
		echo "ERROR: "
		read -p "Please install the \"$pkg\" package, then re-run this script."
		exit 1
	else
		echo -e "\t${pkg} ... installed"
	fi
done

# Make sure there's at least one voice engine.
voiceIndex=0
# Test for Amazon Polly (assume if you have awscli installed, you set up Polly)
if [ $( apt-cache search "Awscli" | grep -i -c "^Awscli - " ) -ne 0 ]
then
	echo -e "\tAwscli ... installed"
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
	echo -e "\t"'$ibm_tts_user'" ... set"
	if [ "$ibm_tts_password" != "x" ] ; then
		echo -e "\t"'$ibm_tts_password'" ... set"
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
fi

# Get a file
clear
echo 'Drag an ".epub", ".pdf", ".html", or ".txt" e-book '
echo 'file; drop it in this window, then press Enter.'
read -p "" source_file

# Remove the single quotes around the file name
# ${var#*SubStr}  # will drop start of string up to first occur of `SubStr`
# ${var##*SubStr} # will drop start of string up to last occur of `SubStr`
# ${var%SubStr*}  # will drop end of string from last occur of `SubStr` to the end
# ${var%%SubStr*} # will drop end of string from first occur of `SubStr` to the end
source_file="${source_file%\'}"
source_file="${source_file#\'}"

# What file extension did we get?
file_ext=${source_file##*.}

# Is the file extension supported by this script?
if [ $( echo epub pdf html txt | grep -i -c ${file_ext} - ) = 0 ]
then
	read -p "The file you dropped is one I can't handle. Sorry!"
	exit 1
fi

# Print the list of voices
clear
echo "Voice List:"
for x in "${voiceArray[@]}"; do
	IFS="|"
		voiceData=(${x})
		echo -e "\t${voiceData[0]}: ${voiceData[1]}"
	unset IFS
done
echo ""
read -p "Please enter the number of the voice you want to use: " user_selection
tts_selection=${voiceArray[${user_selection}]}
IFS="|"
	tts_data=(${tts_selection})
	tts_voice=${tts_data[2]}
	tts_engine=${tts_data[3]}
unset IFS
echo "Using TTS engine: " ${tts_engine}
echo "Using TTS voice: " ${tts_voice}

# The output folder (for .jpeg, .text and .mp3 files) will be the source folder
output_folder=${source_file%\/*}
# Make a working directory so we can generate intermediate files
temp_folder=$(mktemp -d "/tmp/2mp3-XXXXXX") || { read -p "Can't create temp folder, sorry!"; exit 1; }

# Ask for author, title, series, comment, and publish time
clear
echo "Author Name:" 
read -p "" id3_author

clear
echo "Book Title:"
echo -e "\tNote: The title will be the file name. Avoid using "
echo -e "\tthese special characters:  *^|#&!$@?\":'/\\<>[]{}"
read -p "" id3_title

clear
echo "Album/Series Name ["${id3_title}"]:"
read -p "" id3_album
if [ "x"${id3_album} = "x" ]
then
	id3_album=${id3_title}
fi

clear
echo "Comment / Description [none]:" 
read -p "" id3_comment

clear
echo "Publish date [random]: "
echo -e "\tNote: The date can be in almost any format. If you enter a "
echo -e "\tbad format, you'll be asked to re-enter the data. If you "
echo -e "\tenter nothing, a random date from 1970 to 2017 will be used."
epoch_time=''
until [ "x${epoch_time}x" != "xx" ]
do
	read -p "" user_time
	if [ "${user_time}" = "" ]
	then
		# To help sorting tracks by date, we'll create a random start date that we'll 
		# increment for each file. The start will be between 1970-01-01 and 2017-01-01.
		# ... and yes, I know multiplying random numbers doesn't give you random numbers ...
		epoch_time=$(( 86400 + (($RANDOM * $RANDOM * $RANDOM + $RANDOM + $RANDOM + $RANDOM) % 1483171200) ))
		# Round the timestamp to the top of the hour
		epoch_time=$(( (${epoch_time} / 3600) * 3600 ))
		echo "Using random date: " $(date --date="@${epoch_time}" +%Y-%m-%dT%H:%M:%S)
	else
		epoch_time=$( date -d "${user_time}" +%s 2> /dev/null ) || epoch_time=''
		if [ "${epoch_time}" != "" ]; then
			echo "Using date: " $(date --date="@${epoch_time}" +%Y-%m-%dT%H:%M:%S) " (" ${epoch_time} ")"
		else
			echo "Couldn't convert that to a date! Please try again: "
		fi
	fi
done

# Handle things differently if we got EPUB, HTML, or TXT
case $file_ext in
	"epub")
		echo "Extracting HTM/HTML and JPG/JPEG files from the EPUB..."
		# Extract all HTML files from the EPUB into the working directory
		unzip -o -j -d "${temp_folder}" "${source_file}" *.html *.htm *.xhtml > /dev/null 2>&1
		# Extract JPG files into the output folder (and hope one is useful as cover art)
		unzip -o -j -d "${output_folder}" "${source_file}" *.jpg *.jpeg > /dev/null 2>&1
		# The only way I've found to process files in name order is to
		# use normal globbing to fill an array with unsorted file names, 
		# then sort the array.
		declare -a arr
		i=0
		for htmlfile in "${temp_folder}"/*.htm* "${temp_folder}"/*.xhtm*
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
		# Oh, no! Unknown file extension! Redundant since we already tested...
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
rm "${temp_folder}"/*.* > /dev/null

# Split text into <1400 bytes (1500 is Amazon Polly max. 5000 is IBM Watson max, but that's *after* URL-encoding.)
# The "split" function will add a 4-digit suffix
split -a 4 -C 1400 -d --additional-suffix=.txt "${output_folder}"/"${id3_title}".text "${temp_folder}"/"${id3_title}"" - "

# Do text to speech ####################################################
clear
for textfile in "${temp_folder}"/*.txt
do
	echo ""
    mp3file=$(basename "${textfile}" .txt).mp3
    oggfile=$(basename "${textfile}" .txt).ogg
	text_portion=$( cat "${textfile}" )
    case $tts_engine in
			"AWS")
				# Use AWS Polly to create the MP3
				echo "Using AWS to convert ""${textfile}"
				# Remove double quotes (we'll need to pass it as a string on the command line)
				aws_text="${text_portion//\"/\ }"
				aws polly synthesize-speech --output-format mp3 --sample-rate 16000 --voice-id "${tts_voice}" --text "${aws_text}" "${temp_folder}"/"temp1_${mp3file}"
				# Reduce low frequencies (makes speech less natural but clearer)
				sox "${temp_folder}"/"temp1_${mp3file}" "${temp_folder}"/"temp2_${mp3file}" bass -10 400
				# Compand the levels and boost overall volume
				sox "${temp_folder}"/"temp2_${mp3file}" "${output_folder}"/"${mp3file}" compand 0,5 -30.1,-inf,-30,-25,-25,-15,-15,-5,-5,-0.3 -1 -6 gain -n -0.1
				#                                                                               | |  |          |       |       |      |       |  | | 
				#                                                                               | |  |          |       |       |      |       |  | Adjust gain as needed to hit max -0.1dB
				#                                                                               | |  |          |       |       |      |       |  Initial expected level
				#                                                                               | |  |          |       |       |      |       Headroom
				#                                                                               | |  |          |       |       |      Signals at -5dB are boosted to -0.3dB
				#                                                                               | |  |          |       |       Signals at -15dB are boosted to -5dB
				#                                                                               | |  |          |       Signals at -25dB are boosted to -15dB
				#                                                                               | |  |          Signals at -30dB are boosted to -25dB
				#                                                                               | |  Signals less than -30.1dB are removed
				#                                                                               | Decay time is long to prevent rising noise in pauses
				#                                                                               Attack time is fast to quiet loud intros
				rm "${temp_folder}"/"temp1_${mp3file}"
				rm "${temp_folder}"/"temp2_${mp3file}"
				;;
			"IBM")
				# Use IBM Watson to create an OGG, then convert to MP3
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
				curl_url+="?accept=audio/ogg;codecs=vorbis"
				curl_url+="&voice=${tts_voice}"
				curl_url+="&text=${ibm_text}"
				curl -X GET -u "$ibm_tts_user":"$ibm_tts_password" --output "${temp_folder}"/"temp1_${oggfile}" "${curl_url}"
				# Reduce low frequencies (makes speech less natural but clearer)
				sox "${temp_folder}"/"temp1_${oggfile}" "${temp_folder}"/"temp2_${oggfile}" bass -10 400
				# Compand and convert the OGG file to an MP3
				sox "${temp_folder}"/"temp2_${oggfile}" "${output_folder}"/"${mp3file}" compand 0,5 -30.1,-inf,-30,-25,-25,-15,-15,-5,-5,-0.3 -1 -6 gain -n -0.1
				#                                                                               | |  |          |       |       |      |       |  | | 
				#                                                                               | |  |          |       |       |      |       |  | Adjust gain as needed to hit max -0.1dB
				#                                                                               | |  |          |       |       |      |       |  Initial expected level
				#                                                                               | |  |          |       |       |      |       Headroom
				#                                                                               | |  |          |       |       |      Signals at -5dB are boosted to -0.3dB
				#                                                                               | |  |          |       |       Signals at -15dB are boosted to -5dB
				#                                                                               | |  |          |       Signals at -25dB are boosted to -15dB
				#                                                                               | |  |          Signals at -30dB are boosted to -25dB
				#                                                                               | |  Signals less than -30.1dB are removed
				#                                                                               | Decay time is long to prevent rising noise in pauses
				#                                                                               Attack time is fast to quiet loud intros
				# Don't use ffmpeg any longer because sox is better at companding
				# ffmpeg -i "${output_folder}"/"${oggfile}" -ar 16000 -ab 16000 -filter highpass=200 "${output_folder}"/"${mp3file}" 2> /dev/null
				rm "${temp_folder}"/"temp1_${oggfile}"
				rm "${temp_folder}"/"temp2_${oggfile}"
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

# Set ID3 information ##################################################
# If you want to look at mp3 id3 info, use:
# "eyeD3 -v" or "ffprobe" or "id3v2 -l" or "mid3v2 -l" or "operon list"

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
	
	# Unneeded cleaning
	eyeD3 --remove-all "${mp3file}"
	
    # Artist
    #  Specify conversion to 2.3. There's nothing to convert *from*, but
    #  once we start v2.3, all the rest of the writes will honor that version.
    eyeD3 --to-v2.3 --set-text-frame=TPE1:"${id3_author}" "${mp3file}"
    eyeD3 --set-text-frame=TOPE:"${id3_author}" "${mp3file}"
    eyeD3 --set-text-frame=TEXT:"${id3_author}" "${mp3file}"
    eyeD3 --set-text-frame=TOLY:"${id3_author}" "${mp3file}"
	
    # Comment
    if [ "${id3_comment}" ]
    then
		eyeD3 --comment="eng:Comment:${id3_comment}" "${mp3file}"
	fi
	
	# Cover art
    if [ -f "${output_folder}"/cover.jpeg ] # if "cover.jpeg" exists, add it as cover art
    then
        eyeD3 --add-image="${output_folder}"/cover.jpeg:FRONT_COVER:"Cover art" "${mp3file}"
    fi
	
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
    eyeD3 --set-text-frame=TENC:"${encoded_by}" "${mp3file}"

    # Title
    mp3num=${mp3file##*-} # for file name like "foo bar-0012.mp3", returns " 0012.mp3"
	mp3num=${mp3file##* } # for file name like " 0012.mp3", returns "0012.mp3"
    mp3num=${mp3num%%.*} # for string like "0012.mp3", returns "0012"
    mp3title="${id3_title}"" - ""${mp3num}"
    eyeD3 --set-text-frame=TIT2:"${mp3title}" "${mp3file}" # (title)
    
    # Album
    eyeD3 --set-text-frame=TOAL:"${id3_album}" "${mp3file}" # (original album)
    eyeD3 --set-text-frame=TALB:"${id3_album}" "${mp3file}" # (album)

    # Genre
    eyeD3 -G "Speech" "${mp3file}" #TCON (101), which is "Speech"
    
    # Track number
    # Remove leading zeros so we don't have octal problems
	mp3num=$((10#${mp3num})) # Forces "0012" to be decimal 12 (not octal's 10!)
    # Our track number is zero-based, but the max is one-based. Add one to the track!
    mp3num=$(( ${mp3num} + 1 ))
    eyeD3 -N "${numfiles}" "${mp3file}" # Number of tracks
    eyeD3 -n "${mp3num}" "${mp3file}" # Current track

    # Time stamps are different between id3v2.3 and id3v2.4
	# Our preferred time coding method is id3v2.3 where everything is 4-digit numbers
	eyeD3 --set-text-frame=TYER:$(date --date="@${epoch_time}" +%Y) "${mp3file}" # Year
	eyeD3 --set-text-frame=TORY:$(date --date="@${epoch_time}" +%Y) "${mp3file}" # Year
	eyeD3 --set-text-frame=TIME:$(date --date="@${epoch_time}" +%H%M) "${mp3file}" # Hour Minute

	# Add some ID3v1.1 tags just in case we get an old reader
	eyeD3 --to-v1.1 "${mp3file}"
	
	# TDAT (month and day) has to be set and reconstituted because eyeD3 corrupts it to TYER
	eyeD3 --set-text-frame=TDAT:$(date --date="@${epoch_time}" +%m%d) "${mp3file}" # Month Date
	sleep 1 # Give it time to write to the disk (we have to read it on the next step)
	# Convert the MP3 to hex so we can do easy text replacements
	INPUT_2MP3=$( xxd -p "${mp3file}" )
	INPUT_2MP3=$( echo "${INPUT_2MP3}" | tr -d [:space:] )
	# Get our search strings figured out
	TAG_SUFFIX_2MP3="00000005000000"$( echo -n $(date --date="@${epoch_time}" +%m%d)|xxd -p )
	TYER_2MP3=$( echo -n TYER|xxd -p )$TAG_SUFFIX_2MP3 # TYER is the bad string
	TDAT_2MP3=$( echo -n TDAT|xxd -p )$TAG_SUFFIX_2MP3 # TDAT is the good string
	# Now replace the hex file's TYER tag with the TDAT tag we want
	OUTPUT_2MP3=${INPUT_2MP3//$TYER_2MP3/$TDAT_2MP3}
	# Did the substitution work?
	if [ "${OUTPUT_2MP3}" = "${INPUT_2MP3}" ]
	then
		echo "TDAT tag was not recovered - old:${TYER_2MP3}, new:${TDAT_2MP3}"
		read -p ""
	else
		echo "TDAT tag was recovered"	
		# Convert the edited text back into a binary MP3
		echo $OUTPUT_2MP3 | xxd -r -p > "${mp3file}"
	fi
	
    # Time stamps will increment one minute (60 seconds) for each track
	epoch_time=$(( $epoch_time + 60 ))
    
    # Make the file timestamp match the ID3 timestamp due to Android limitation
    # touch -d "$(date --date=@${epoch_time} +'%m/%d %Y %H:%M')" "${mp3file}"
done
