cmake_minimum_required(VERSION 3.10)

project(my_sast_project C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

add_executable(my_sast_project main.c utils.c)
