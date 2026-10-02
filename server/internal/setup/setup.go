// Package setup implements the interactive configuration and the macOS background service.
package setup

import "errors"

var errTodo = errors.New("non ancora disponibile")

func Run(dataDir, version string) error { return errTodo }
func Status(dataDir string) error       { return errTodo }
func Uninstall(dataDir string) error    { return errTodo }
