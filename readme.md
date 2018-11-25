## Publish

A shell script I cobbled together to create a static website with navigation based on folder structure of your posts.
Result is similar to [my own site](https://proxygeek.github.io).

### Intro

Based off a lightly modified version of [Expose](https://github.com/Jack000/Expose) - a wonderful bash script by [Jack Qiao](http://jack.works/)
Theme is based off [Hyde](https://github.com/poole/hyde) but you can change it easily by just replacing the theme directory.

It's **current state is essentially a template of how _NOT_ to write a shell script.**
The mess is my own fault but I will keep improving it whenever I can. In the mean time, it works! Sort of...   


### Installation

The only optional dependency are [Markdown script](https://daringfireball.net/projects/markdown/) and [Perl](https://www.perl.org/get.html) for Markdown support.

Download the repo and alias the script

	alias publish=/script/location/publish.sh

for permanent use add this line to your ~/.profiles, ~/.bashrc etc depending on system


### Basic usage

	cd ~/folder_of_text_files
	publish

* * * * 
	
The script operates on your current working directory, and outputs a _site directory.

- Your-Folder  
	- SubFolder-1  
		- post_1.txt  
		- post_2.md  
	- SubFolder-2  
		- another_post.md  
	- SubFolder-3  
	....  
	- SubFolder-n  

Just run the script in **_Your-Folder_** and it will generate a static website under **_Your-Folder/_site/_** directory.
The subdirectories will be treated as different sections of the website and navigation will be generated accordingly.
Empty directories will be ignored.

* * * * 


### Configuration
You can configure some variables to set your website title, sub-title, theme-directory and more through the _config.sh

Details to be updated

### Current issues
- Refactor the code to remove redundant logic and restructure for clarity
- Fix post tag search / links , especially in case of multiple tags for a post
- Generate section level tag cloud from individual post tags: dir_tag_cloud
- Number of (and links to) top posts to be read from config file in the top directory
- Pick up related posts from YAML. say related_posts:post1,post2
- Sort command changes made to process the files / dirs in the order of most recent updates causes an additional directory to be created under _site directory
	- Can be easily fixed by using the alphabetical sort instead - currently commented out 
- _And many, many more but none that should stop you from giving this a whirl :) _

