all: clean client server

clean:
	rm -rf target
	
client:
	mkdir -p target/client/bin
	cp readme/client-readme target/client/README
	cp git-lock target/client/bin
	cp lock-client-lib.sh target/client/bin
	cp lock-util.sh target/client/bin
	cp pre-receive target/client/bin
	tar -cf target/client.tar -C target/client .
	
server:
	mkdir -p target/server/bin
	mkdir -p target/server/lock-working-dir
	cp readme/server-readme target/server/README
	cp lock-server.sh target/server/bin
	cp lock-server-lib.sh target/server/bin
	cp lock-util.sh target/server/bin
	tar -cf target/server.tar -C target/server .
