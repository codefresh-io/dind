package main

import (
	"flag"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net"
	"net/http"
	"os"
	"sync"
	"sync/atomic"

	"github.com/docker/go-connections/sockets"
	"github.com/kvz/logstreamer"
)

const dockerSocketPath = "/var/run/docker.sock"

type handler struct{}

func (h handler) ServeHTTP(w http.ResponseWriter, req *http.Request) {

	var counter uint64
	var sockDebug = ioutil.Discard
	var connDebug = ioutil.Discard

	requestID := atomic.AddUint64(&counter, 1)

	l := log.New(os.Stderr, fmt.Sprintf("#%d ", requestID), log.Ltime|log.Lmicroseconds)

	if *debugFlag == true {
		sockStreamer := logstreamer.NewLogstreamer(l, "> ", false)
		sockDebug = sockStreamer
		defer sockStreamer.Close()

		connStreamer := logstreamer.NewLogstreamer(l, "< ", false)
		connDebug = connStreamer
		defer connStreamer.Close()
	}

	sock, err := net.Dial("unix", dockerSocketPath)
	if err != nil {
		http.Error(w, "Error communicating with the docker daemon", 500)
		return
	}

	defer sock.Close()

	hj, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "Not a Hijacker?", 500)
		return
	}

	reqConn, bufrw, err := hj.Hijack()
	if err != nil {
		l.Printf("Hijack error: %v", err)
		return
	}

	defer reqConn.Close()

	req.Header.Set("User", "freestyle")
	req.Header.Set("Connection", "close")

	// write the request to the docker socket
	err = req.Write(io.MultiWriter(sock, sockDebug))
	if err != nil {
		l.Printf("Error copying request to target: %v", err)
		return
	}

	// handle anything already buffered from before the hijack
	if bufrw.Reader.Buffered() > 0 {
		l.Printf("Found %d bytes buffered in reader", bufrw.Reader.Buffered())
		rbuf, err := bufrw.Reader.Peek(bufrw.Reader.Buffered())
		if err != nil {
			panic(err)
		}

		l.Printf("Buffered: %s", rbuf)
		panic("Buffered bytes not handled")
	}

	var wg sync.WaitGroup
	wg.Add(2)

	// Copy from request to the docker socket (upstream connection)
	go func() {
		defer wg.Done()
		n, err := io.Copy(io.MultiWriter(sock, sockDebug), reqConn)
		if err != nil {
			l.Printf("Error copying request to socket: %v", err)
		}
		l.Printf("Copied %d bytes from downstream connection", n)
	}()

	// copy from the docker socket to the downstream connection
	go func() {
		defer wg.Done()
		n, err := io.Copy(io.MultiWriter(reqConn, connDebug), sock)
		if err != nil {
			l.Printf("Error copying socket to request: %v", err)
		}
		l.Printf("Copied %d bytes from upstream socket", n)

		if err := bufrw.Flush(); err != nil {
			l.Printf("Error flushing buffer: %v", err)
		}
		if err := reqConn.Close(); err != nil {
			l.Printf("Error closing connection: %v", err)
		}
	}()

	wg.Wait()
	l.Printf("Done, closing")
}

var proxySocketPath = flag.String("proxy-socket", "/var/run/plugin-proxy.sock", "Specify the unix socket path for the proxy to listen on")

func startProxy(gid int) {
	var h handler
	server := http.Server{Handler: h}

	unixListener, err := sockets.NewUnixSocket(*proxySocketPath, gid)
	if err != nil {
		panic(err)
	}

	server.Serve(unixListener)
}
