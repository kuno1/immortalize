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

func run(minLifetime uint, maxLifetime uint, command string) {
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

	if 0 < maxLifetime {
		go func() {
			time.Sleep(time.Duration(maxLifetime) * time.Second)
			log.Info("Maximum lifetime has passed.")
			cmd.Process.Signal(syscall.SIGTERM)
			log.Info("Signal 'terminated' has been sent to the process.")
		}()
	}

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
				log.Infof("Signal '%v' has been received.", s)
				<-lifetimeChan
			}
			cmd.Process.Signal(s)
			log.Infof("Signal '%v' has been forwarded to the process.", s)
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
	minLifetimePtr := flag.Uint("min-lifetime", 0,
		"Time duration for minimum process lifetime in seconds")
	maxLifetimePtr := flag.Uint("max-lifetime", 0,
		"Time duration for maximum process lifetime in seconds")
	commandPtr := flag.String("command", "command", "command to immortalize")
	levelPtr := flag.String(
		"log-level", "info", "Log level: 'info', 'debug', or 'trace'")
	flag.Parse()

	configLog(*levelPtr)

	log.Debugf("PID: %v", os.Getpid())

	if 0 < *maxLifetimePtr && *maxLifetimePtr < *minLifetimePtr {
		log.Fatal("min-lifetime cannot be higher than max-lifetime.")
	}

	run(*minLifetimePtr, *maxLifetimePtr, *commandPtr)
}
