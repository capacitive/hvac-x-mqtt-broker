package cmd

type OutTreeDir struct {
	BoardDir
	Buildroot string `default:"buildroot"`
	Configs   string `default:"configs"`
	Package   string `default:"package"`
	RootFiles
}

type RootFiles struct {
	Configin     string `default:"Config.in"`
	ExternalDesc string `default:"external.desc"`
	ExternalMk   string `default:"external.mk"`
}

type BoardDir struct {
	Name string `default:"board"`
	ProjectDir
	CommmonDir
}

type ProjectDir struct {
	Name          string `default:"hvacx"`
	Patches       string `default:"patches"`
	RootFsOverlay string `default:"rootfs_overlay"`
}

type CommmonDir struct {
	Name          string `default:"common"`
	Patches       string `default:"patches"`
	RootFsOverlay string `default:"rootfs_overlay"`
}
