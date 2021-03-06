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

func run(minLifetime uint, maxLifetime uint, command string) int {
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

	var status int
	if err := cmd.Wait(); err != nil {
		if e2, ok := err.(*exec.ExitError); ok {
			if s, ok := e2.Sys().(syscall.WaitStatus); ok {
				status = s.ExitStatus()
			} else {
				log.Fatal("Failed to execute command")
			}
		}
	} else {
		status = 0
	}

	return status
}

func configLog(level string, logPath string) error {
	var l logrus.Level
	switch level {
	case "trace":
		l = logrus.TraceLevel
	case "debug":
		l = logrus.DebugLevel
	case "info":
		l = logrus.InfoLevel
	default:
		return errors.New("log level must be one of 'info', 'debug', or 'trace'")
	}

	log.SetFormatter(&logrus.JSONFormatter{})
	log.SetLevel(l)

	if logPath == "" {
		log.Out = os.Stderr
		return nil
	}

	f, err := os.Create(logPath)
	if err != nil {
		return err
	}
	log.Out = f
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
	logPathPtr := flag.String(
		"log-path", "", "Log path: default to stderr")
	flag.Parse()

	if err := configLog(*levelPtr, *logPathPtr); err != nil {
		panic(err)
	}

	log.Debugf("PID: %v", os.Getpid())

	if 0 < *maxLifetimePtr && *maxLifetimePtr < *minLifetimePtr {
		log.Fatal("min-lifetime cannot be higher than max-lifetime.")
	}

	os.Exit(run(*minLifetimePtr, *maxLifetimePtr, *commandPtr))
}
