package audit

import (
	"context"
	"fmt"
	"log/slog"
	"sync"
)

// Service is the interface the rest of the codebase calls to write audit events.
// The async implementation enqueues events and writes them off the request path.
type Service interface {
	// WriteAsync enqueues an audit event. Never returns an error to the caller —
	// audit failures are logged but must not break the request.
	WriteAsync(ctx context.Context, e Event)
}

// AsyncService is the production implementation. It runs a background worker
// that drains a buffered channel and writes to the repository.
type AsyncService struct {
	repo    Repository
	queue   chan Event
	mu      sync.Mutex
	stopped bool
	done    chan struct{}
}

const queueSize = 1024

// NewAsyncService constructs the audit service and starts the background writer.
// Call Stop() on shutdown to drain the queue.
func NewAsyncService(repo Repository) *AsyncService {
	s := &AsyncService{
		repo:  repo,
		queue: make(chan Event, queueSize),
		done:  make(chan struct{}),
	}
	go s.drain()
	return s
}

// WriteAsync enqueues an event. If the queue is full or the service has been
// stopped, the event is dropped and logged — availability beats perfect audit
// completeness.
func (s *AsyncService) WriteAsync(ctx context.Context, e Event) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.stopped {
		slog.Warn("audit service stopped — event dropped", "event", e.Event)
		return
	}
	select {
	case s.queue <- e:
	default:
		slog.Warn("audit queue full — event dropped", "event", e.Event)
	}
}

// Stop drains remaining events and shuts down the worker. Call on server shutdown.
func (s *AsyncService) Stop() {
	s.mu.Lock()
	s.stopped = true
	close(s.queue)
	s.mu.Unlock()
	<-s.done
}

func (s *AsyncService) drain() {
	defer close(s.done)
	for e := range s.queue {
		// Use a background context — the original request context may be cancelled.
		if err := s.repo.Insert(context.Background(), e); err != nil {
			slog.Error("audit write failed", "event", e.Event, "err", fmt.Sprintf("%v", err))
		}
	}
}
