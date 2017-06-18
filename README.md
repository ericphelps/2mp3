<h1>2mp3.sh</h1>
<br />Converts an EPUB, HTML or TXT e-book file into a set of MP3 files (an audio book!)
<br />Windows has nice voices available (at a price), but Linux has nothing (espeak, festival, flite, and pico2wave are all horrible). So to convert an e-book into an audio book, we'll use Amazon or IBM's very good voices. Amazon's "Joanna" is by far the best (and free for a year), but IBM's "Lisa" and "Michael" are also very good -- and effectively free forever if you limit yourself to about 10 books a month.
<br />In addition to creating the MP3 files, this script also tags the files with ID3 data to make the files easier to identify and sort in your audio player.
<br />REQUIREMENTS (will be tested by the script):
<ul>
<li>operon (to add cover art to the MP3) needs the Quodlibet package 
<li>html2text needs the Html2text package
<li>pdftotext needs the Poppler-utils package
<li>curl needs the Curl package
<li>ffmpeg needs the Ffmpeg package
<li>ID3 tagging needs at least one of the following ID3 tag editors:
	<ul>
	<li>mid3v2 needs the Python-mutagen package
	<br /><i>The mid3v2 program creates newer (more detailed) version 2.4 tags</i>
	<li>id3v2 needs the Id3v2 package
	<br /><i>The id3v2 program creates older (more compatible) version 2.3 tags</i>
	</ul>
<li>TTS needs at least one of the following cloud voice engines:
	<ul>
	<li>AMAZON:
		<ul>
		<li>aws needs the Awscli package 
		<li>A free Amazon Web Services account set up per steps 1 & 3 at: 
		<br />http://docs.aws.amazon.com/polly/latest/dg/getting-started.html
		</ul>
	<li>IBM:
		<ul>
		<li>A free IBM/BlueMix account set up per the "Start free" link at:
		<br />https://www.ibm.com/watson/developercloud/text-to-speech.html
		<li>Credentials for the TTS service set up per the directions at:
		<br />https://www.ibm.com/watson/developercloud/doc/common/getting-started-credentials.html#getting-credentials-manually
		<li>Add the IBM credentials to the environment e.g., by editing "~/.profile" to include (but using real creds!):
		<br />export ibm_tts_user=abcd0123-ef45-ab01-cd67-ef23456789ab
		<br />export ibm_tts_password=A1bC2dE3fG4h
		</ul>
	</ul>
</ul>
