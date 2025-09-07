package logger

import (
	"bufio"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"sync"

	"github.com/gorilla/websocket"
	"google.golang.org/grpc"
)

type LogEntry struct {
	Message string `json:"message"`
}

type LogServer struct {
	clients map[chan string]bool
	mu      sync.RWMutex
	buffer  []string
}

var (
	upgrader  = websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }}
	logServer = &LogServer{
		clients: make(map[chan string]bool),
		buffer:  make([]string, 0, 20),
	}
)

func (s *LogServer) addToBuffer(msg string) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if len(s.buffer) >= 20 {
		s.buffer = s.buffer[1:]
	}
	s.buffer = append(s.buffer, msg)
}

func (s *LogServer) broadcast(msg string) {
	s.addToBuffer(msg)

	s.mu.RLock()
	defer s.mu.RUnlock()

	for client := range s.clients {
		select {
		case client <- msg:
		default:
			close(client)
			delete(s.clients, client)
		}
	}
}

func wsHandler(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	defer conn.Close()

	client := make(chan string, 100)

	logServer.mu.Lock()
	logServer.clients[client] = true
	for _, msg := range logServer.buffer {
		conn.WriteJSON(LogEntry{Message: msg})
	}
	logServer.mu.Unlock()

	defer func() {
		logServer.mu.Lock()
		delete(logServer.clients, client)
		logServer.mu.Unlock()
		close(client)
	}()

	for msg := range client {
		if err := conn.WriteJSON(LogEntry{Message: msg}); err != nil {
			break
		}
	}
}

func StartLogServices() {
	go func() {
		http.HandleFunc("/logs", wsHandler)
		log.Println("WebSocket server starting on :8080")
		http.ListenAndServe(":8080", nil)
	}()

	go func() {
		lis, err := net.Listen("tcp", ":9090")
		if err != nil {
			log.Fatal(err)
		}

		s := grpc.NewServer()
		log.Println("gRPC server starting on :9090")
		s.Serve(lis)
	}()
}

func BroadcastLog(msg string) {
	fmt.Println(msg)
	logServer.broadcast(msg)
}

func StreamStdin() {
	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		line := scanner.Text()
		BroadcastLog(line)
	}
}