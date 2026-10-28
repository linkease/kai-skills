package main
import (
 "fmt"
 "github.com/google/uuid"
)
func main() {
 value, err := uuid.Parse("123e4567-e89b-12d3-a456-426614174000")
 if err != nil { panic(err) }
 fmt.Println(value.String())
}
