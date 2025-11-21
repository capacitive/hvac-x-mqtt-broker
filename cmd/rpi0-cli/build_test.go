package cmd

import (
	cmd "hvac-x-hub-min/cmd/filesystem"
	"testing"
)

func TestRpiZeroOps(t *testing.T) {

	t.Run("init filesystem", func(t *testing.T) {
		dir := cmd.NewOutTreeFS()
		board := dir.BoardDir

		got := board.Name
		want := "board"

		if got != want {
			t.Errorf("got %s want %s", got, want)
		}

		got = board.CommmonDir.RootFsOverlay
		want = "rootfs_overlay"

		if got != want {
			t.Errorf("got %s want %s", got, want)
		}
	})

	t.Run("create directory", func(t *testing.T) {
		dir, err := cmd.CreateOutTreeDir("board")
		if err != nil {
			t.Fatal(err)
		}

		got := dir
		want := "board"

		if got != want {
			t.Errorf("got \"%s\", want \"%s\"", got, want)
		}

		errdelete := cmd.DeleteOutTreeDir("board")
		if errdelete != nil {
			t.Fatal(errdelete)
		}

	})

	// t.Run("read dir board", func(t *testing.T) {
	// 	t.Skip()
	// 	dir, err := fs.ReadDir(board, ".")
	// 	if err != nil {
	// 		t.Fatal(err)
	// 	}
	//
	// 	got := dir[0].Name()
	// 	want := "build"
	//
	// 	if got != want {
	// 		t.Errorf("got %s want %s", got, want)
	// 	}
	// })
}
