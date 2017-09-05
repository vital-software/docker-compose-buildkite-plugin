package main

import (
	"fmt"
	"os"

	"github.com/urfave/cli"
)

type Config struct {
}

func main() {
	app := cli.NewApp()

	app.Action = func(ctx *cli.Context) error {
		fmt.Printf("Llamas")
		return nil
	}

	app.Commands = []cli.Command{
		{
			Name: "build",
			Action: func(c *cli.Context) error {
				fmt.Println("building: ", c.Args().First())
				return nil
			},
		},
		{
			Name: "push",
			Action: func(c *cli.Context) error {
				fmt.Println("pushing: ", c.Args().First())
				return nil
			},
		},
		{
			Name: "run",
			Action: func(c *cli.Context) error {
				fmt.Println("running: ", c.Args().First())
				return nil
			},
		},
	}

	app.Run(os.Args)
}
