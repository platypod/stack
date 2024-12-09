package main // wait4sigint

import (
	"fmt"
	"os"
	"os/signal"
	"syscall"
)

func wait4sigint() {
	done := make(chan os.Signal, 1)
	signal.Notify(done, syscall.SIGINT, syscall.SIGTERM)
	fmt.Println("block until SIGINT")
	<-done
}

func main() {
	wait4sigint()
}
