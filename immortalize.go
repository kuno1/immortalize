package main

import (
	"errors"
	"flag"
	"github.com/sirupsen/logrus"
	"os"
	"os/exec"
	"os/signal"
	"syscall"
	"time"
)

var log = logrus.New()

func run(minLifetime int, command string) {
	cmd := exec.Command(command)
	cmd.Stderr = os.Stderr
	cmd.Stdout = os.Stdout

	signalChan := make(chan os.Signal, 1)
	signal.Notify(signalChan,
		syscall.SIGHUP,
		syscall.SIGTERM,
		syscall.SIGINT,
		syscall.SIGQUIT)

	cmd.Start()

	lifetimeChan := make(chan bool)

	go func() {
		time.Sleep(time.Duration(minLifetime) * time.Second)
		log.Info("Minimum lifetime has passed.")
		for {
			lifetimeChan <- true
		}
	}()

	go func() {
		for s := range signalChan {
			if s == syscall.SIGTERM {
				log.Info("SIGTERM has been received.")
				<-lifetimeChan
			}
			log.Infof("Signal '%v' has been forwarded to the process.", s)
			cmd.Process.Signal(s)
		}
	}()

	cmd.Wait()
}

func configLog(level string) error {
	var l logrus.Level
	switch level {
	case "trace":
		l = logrus.TraceLevel
	case "debug":
		l = logrus.DebugLevel
	case "info":
		l = logrus.DebugLevel
	default:
		return errors.New("log level must be one of 'info', 'debug', or 'trace'")
	}

	log.SetFormatter(&logrus.JSONFormatter{})
	log.SetLevel(l)
	log.Out = os.Stderr
	return nil
}

func main() {
	minLifetimePtr := flag.Int("min-lifetime", 0,
		"Time duration for minimum process lifetime in seconds")
	commandPtr := flag.String("command", "command", "command to immortalize")
	levelPtr := flag.String(
		"log-level", "info", "Log level: 'info', 'debug', or 'trace'")
	flag.Parse()

	configLog(*levelPtr)

	log.Debugf("PID: %v", os.Getpid())

	run(*minLifetimePtr, *commandPtr)
}
