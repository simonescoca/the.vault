//go:build !unix

package backup

// lockDir does nothing where the server does not run as a service (it is built for macOS and Linux).
func lockDir(string) (func(), error) { return func() {}, nil }
