# 2mp3
Converts an EPUB, HTML or TXT e-book file into a set of MP3 files (Linux/Bash)
REQUIREMENTS:
operon (to add cover art to the MP3) needs the Quodlibet package 
html2text needs the Html2text package
pdftotext needs the Poppler-utils package
ID3 tagging needs at least one of the following ID3 tag editors:
MID3V2:
	mid3v2 needs the Python-mutagen package
	The mid3v2 program creates newer (more detailed) version 2.4 tags
ID3V2:
	id3v2 needs the Id3v2 package
	The id3v2 program creates older (more compatible) version 2.3 tags
TTS needs at least one of the following cloud voice engines:
	AMAZON:
	  aws needs the Awscli package 
	  A free Amazon Web Services account set up per steps 1 & 3 at: 
    http://docs.aws.amazon.com/polly/latest/dg/getting-started.html
	IBM:
		A free IBM/BlueMix account set up per the "Start free" link at:
		https://www.ibm.com/watson/developercloud/text-to-speech.html
		Credentials for the TTS service set up per the directions at:
		https://www.ibm.com/watson/developercloud/doc/common/getting-started-credentials.html#getting-credentials-manually
		Add the IBM credentials to the environment e.g., by editing "~/.profile" to include (but using real creds!):
		export ibm_tts_user=abcd0123-ef45-ab01-cd67-ef23456789ab
		export ibm_tts_password=A1bC2dE3fG4h
