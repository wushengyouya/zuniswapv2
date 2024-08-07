package main

import (
	"fmt"
	"math"
)

func main() {
	fmt.Println(price_to_tick(5000))
	fmt.Println(price_to_sqrtp(5000))
	fmt.Println(math.Pow(10, 2))
}

func price_to_tick(p float64) float64 {
	logValue := math.Log(p) / math.Log(1.0001)
	tick := math.Floor(logValue)
	return tick
}

func price_to_sqrtp(p float64) float64 {
	q96 := math.Pow(2, 96)
	return math.Sqrt(p) * q96

}
