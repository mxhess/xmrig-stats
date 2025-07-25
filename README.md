Designed to look like a curses style console similar to htop but in a web browser showing the stats from xmrig-proxy
![Model](https://github.com/mxhess/xmrig-stats/blob/main/Screenshot.png)


Browser does much of the work and this requires nothing from the webserver.
We do need a valkey instance running locally so we can cache the gathered data from the proxy
and running the xmrig_stats.py python script will require minimal python additions.

you need the python redis and requests packages

general install:

install valkey
install python redis and requests packages
copy service file and edit for whatever non-privlidged user will be running it
enable and start the xmrig-stats service

both of these commands should return:

python3.13 -c "import redis; print(redis.__version__)"
 >= 6.2.0
python3.13 -c "import requests; print(requests.__version__)"
 >= 2.32.4


I do assume you are running the xmrig-proxy as a service as well and made the stats service dependent upon it.
If you need, I included a general xmrig-proxy.service file in case that helps.

I included a shell script to manage the active xmrig-proxy pool that you can use with cron to automatically redirect your proxy at certain times or trigger given certain conditions.

switch_pool.sh usage:

./switch_pool.sh matching.url.from.config.including:port

ex:

./switch_pool.sh gulf.moneroocean.stream:20128

and the script will enable that specific pool and disable all other pools

excellent way to schedule pool switching in xmrig-proxy without a bunch of fancy setup or front ends

only requires jq to be installed and available on command line


