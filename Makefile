all:
	stat memcp || (git clone https://github.com/launix-de/memcp; cd memcp; go get)
	make -C memcp

