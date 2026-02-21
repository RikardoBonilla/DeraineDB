package server

import (
	"fmt"
	"unsafe"

	"github.com/prometheus/client_golang/prometheus"
)

/*
#cgo CFLAGS: -I../../core/include
#cgo LDFLAGS: -L../../core/zig-out/lib -lcore
#include "deraine_core.h"
#include <stdlib.h>
*/
import "C"

type DeraineCollector struct {
	dbHandle unsafe.Pointer

	vectorsTotal  *prometheus.Desc
	indexLevelMax *prometheus.Desc
	healthy       *prometheus.Desc
	version       *prometheus.Desc
}

func NewDeraineCollector(handle unsafe.Pointer) *DeraineCollector {
	return &DeraineCollector{
		dbHandle: handle,
		vectorsTotal: prometheus.NewDesc(
			"deraine_vectors_total",
			"Total number of vectors actively stored in the engine.",
			nil, nil,
		),
		indexLevelMax: prometheus.NewDesc(
			"deraine_hnsw_level_max",
			"Current maximum level attained by the HNSW graph.",
			nil, nil,
		),
		healthy: prometheus.NewDesc(
			"deraine_engine_healthy",
			"Binary health status (1 = Healthy, 0 = Error).",
			nil, nil,
		),
		version: prometheus.NewDesc(
			"deraine_engine_version_info",
			"DeraineDB version information.",
			[]string{"version"}, nil,
		),
	}
}

func (c *DeraineCollector) Describe(ch chan<- *prometheus.Desc) {
	ch <- c.vectorsTotal
	ch <- c.indexLevelMax
	ch <- c.healthy
	ch <- c.version
}

func (c *DeraineCollector) Collect(ch chan<- prometheus.Metric) {
	var status C.deraine_status_t
	res := C.deraine_get_status(c.dbHandle, &status)

	isHealthy := 0.0
	if res == 0 && status.healthy != 0 {
		isHealthy = 1.0
	}

	ch <- prometheus.MustNewConstMetric(c.healthy, prometheus.GaugeValue, isHealthy)

	if res == 0 {
		ch <- prometheus.MustNewConstMetric(c.vectorsTotal, prometheus.GaugeValue, float64(status.vector_count))
		ch <- prometheus.MustNewConstMetric(c.indexLevelMax, prometheus.GaugeValue, float64(int32(status.max_level)))
		ch <- prometheus.MustNewConstMetric(c.version, prometheus.GaugeValue, 1, fmt.Sprintf("v%d.0", status.version))
	}
}
