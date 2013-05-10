all: client server
	
client:
	mkdir -p target/client/bin
	mkdir -p target/client/hooks
	cp readmes/client-readme target/client/README
	cp git-lock target/client/bin
	cp lock-client-lib.sh target/client/bin
	cp lock-util.sh target/client/bin
	cp hook-base.sh target/client/bin
	cp hooks/* target/client/hooks
	tar -cf target/client.tar -C target/client .
	
server:
	mkdir -p target/server/bin
	mkdir -p target/server/lock-working-dir
	cp readmes/server-readme target/server/README
	cp lock-server.sh target/server/bin
	cp lock-server-lib.sh target/server/bin
	cp lock-util.sh target/server/bin
	tar -cf target/server.tar -C target/server .
	
clean:
	rm -rf target