Designed to look like a curses style console similar to htop but in a web browser showing the stats from xmrig-proxy
![Model](https://github.com/mxhess/xmrig-stats/blob/main/Screenshot.png)


Browser does the work and this requires nothing from the webserver.

included script to manage active xmrig-proxy pool

switch_pool.sh usage:

./switch_pool.sh matching.url.from.url:including:port

ex:

./switch_pool.sh gulf.moneroocean.stream:20128

and the script will enable that specific pool and disable all other pools

excellent way to schedule pool switching in xmrig-proxy without a bunch of fancy setup or front ends

only requires jq to be installed and available on command line


