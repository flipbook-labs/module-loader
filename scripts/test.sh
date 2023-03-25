#!/usr/bin/env bash

rojo build dev.project.json -o studio-tests.rbxl
run-in-roblox --place studio-tests.rbxl --script tests/init.server.lua
