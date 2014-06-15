svnremotenotify
===============

SVN Remote Notify sends SVN changes on defined SVN URL to your email.
Each new revision is sent separately including diff attachment.

It uses file `notified.revs` (or as defined by `--notified`) to save last notified revision for SVN URL and email.

Usage
-----

~~~
Usage: ./svnremotenotify.pl -u <URL> -t <EMAIL>

Options:
    -u --url   <SVNURL>
    -t --to    <EMAIL>
    --notified <NOTFIED_FILE_PATH>
    -m --max   <MAX_DIFF_REVISIONS> default 10
~~~

Crontab examples
-------------

~~~
SVN_EXAMPLE=svn+ssh://svn.example.com/home/svn/project/trunk
SVNNOTIFY=svnremotenotify/svnremotenotify.pl -t your@email.com --notified svnremotenotify/notfied.revs

# Run every 2 minutes from 8am to 8pm
*/2 8-20 * * * $SVNNOTIFY -u $SVN_EXAMPLE > /dev/null

# Run every 10 minutes from 9pm to 11pm
*/10 21-23 * * * $SVNNOTIFY -u $SVN_EXAMPLE > /dev/null
~~~

