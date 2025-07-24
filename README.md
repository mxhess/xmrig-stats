Designed to look like a curses style console similar to htop but in a web browser showing the stats from xmrig-proxy
![Model](https://github.com/mxhess/xmrig-stats/blob/main/Screenshot.png)


Browser does much of the work and this requires nothing from the webserver.
We do need a valkey instance running locally so we can cache the gathered data from the proxy
and running the xmrig_stats.py python script will require minimal python additions.

you need the python redis and requests packages


included script to manage active xmrig-proxy pool

switch_pool.sh usage:

./switch_pool.sh matching.url.from.url:including:port

ex:

./switch_pool.sh gulf.moneroocean.stream:20128

and the script will enable that specific pool and disable all other pools

excellent way to schedule pool switching in xmrig-proxy without a bunch of fancy setup or front ends

only requires jq to be installed and available on command line


