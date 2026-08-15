/*
Copyright 2026.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
)

// MaintenanceSpec defines the desired state of Maintenance.
type MaintenanceSpec struct {

	// Name of the target Ingress.
	//
	// This supported targeting mode reads the target Ingress for ALB metadata,
	// then creates one standalone catch-all maintenance Ingress in the same
	// ALB IngressGroup.
	// +optional
	TargetIngress string `json:"targetIngress,omitempty"`

	// ALB IngressGroup name to place into maintenance.
	//
	// This recommended targeting mode creates a standalone catch-all maintenance
	// Ingress in the specified ALB IngressGroup, without requiring users to
	// identify or mirror an existing application Ingress.
	//
	// The operator discovers existing same-namespace Ingresses with this group
	// name to resolve listener ports for the generated maintenance Ingress.
	// +kubebuilder:validation:MinLength=1
	// +optional
	ALBGroupName string `json:"albGroupName,omitempty"`

	// MaintenanceMode is the master switch for maintenance behavior.
	// When false or omitted, maintenance is disabled and Schedule is ignored.
	// When true, maintenance starts immediately unless Schedule narrows the
	// active window.
	// +optional
	MaintenanceMode *bool `json:"maintenanceMode,omitempty"`

	// Maintenance response configuration.
	// +optional
	Response *MaintenanceResponse `json:"response,omitempty"`

	// Optional ALB group order for the maintenance ingress.
	// Lower values take precedence over higher values.
	// +kubebuilder:validation:Minimum=0
	// +kubebuilder:default=0
	// +optional
	Priority int `json:"priority,omitempty"`

	// Optional maintenance schedule.
	// When set with MaintenanceMode=true, maintenance is enabled inside the
	// start/end window and disabled outside it.
	// +optional
	Schedule *MaintenanceSchedule `json:"schedule,omitempty"`
}

// MaintenanceResponse defines how the maintenance response is served.
type MaintenanceResponse struct {

	// HTML returned directly from the load balancer.
	// Used when Backend=fixed-response.
	//
	// AWS ALB fixed-response has size limitations.
	//
	// +kubebuilder:validation:MaxLength=1024
	// +optional
	HTML string `json:"html,omitempty"`

	// Automatically deploy an NGINX backend
	// for larger maintenance pages.
	//
	// Used when Backend=nginx.
	//
	// +optional
	UseNginx bool `json:"useNginx,omitempty"`

	// Backend implementation used to serve maintenance response.
	//
	// fixed-response - Return HTML from ingress/load balancer.
	//
	// +kubebuilder:validation:Enum=fixed-response
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:default=fixed-response
	// +optional
	Backend string `json:"backend,omitempty"`

	// Existing Kubernetes Service name.
	// Used when Backend=service.
	//
	// +optional
	ServiceName string `json:"serviceName,omitempty"`
}

// MaintenanceSchedule defines the maintenance window.
type MaintenanceSchedule struct {

	// Maintenance start time (RFC3339), for example 2026-09-01T22:00:00Z
	// or 2026-09-01T18:00:00-04:00 for an ET offset.
	// +optional
	Start *metav1.Time `json:"start,omitempty"`

	// Maintenance end time (RFC3339), for example 2026-09-01T23:00:00Z
	// or 2026-09-01T19:00:00-04:00 for an ET offset.
	// +optional
	End *metav1.Time `json:"end,omitempty"`
}

// MaintenanceStatus defines the observed state of Maintenance.
type MaintenanceStatus struct {

	// Current reconciliation phase.
	//
	// Pending - Resource detected but not processed yet.
	// Enabled  - Maintenance rules applied successfully.
	// Disabled - Maintenance ingress removed.
	// Failed   - Reconciliation failed.
	//
	// +kubebuilder:validation:Enum=Pending;Enabled;Disabled;Failed
	// +optional
	Phase string `json:"phase,omitempty"`

	// Whether a backup of the target Ingress exists.
	//
	// +optional
	BackupCreated bool `json:"backupCreated,omitempty"`

	// Name of the backup resource containing the original Ingress.
	//
	// +optional
	BackupResourceName string `json:"backupResourceName,omitempty"`

	// ResourceVersion of the target Ingress when maintenance was enabled.
	//
	// Used to detect changes while maintenance mode is active.
	//
	// +optional
	TargetIngressResourceVersion string `json:"targetIngressResourceVersion,omitempty"`

	// Last time the controller changed the phase.
	//
	// +optional
	LastTransitionTime *metav1.Time `json:"lastTransitionTime,omitempty"`

	// Human-readable status message.
	//
	// +optional
	Message string `json:"message,omitempty"`

	// Current resource conditions.
	//
	// +optional
	Conditions []metav1.Condition `json:"conditions,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:printcolumn:name="Ingress",type=string,JSONPath=`.spec.targetIngress`
// +kubebuilder:printcolumn:name="ALBGroup",type=string,JSONPath=`.spec.albGroupName`
// +kubebuilder:printcolumn:name="Mode",type=boolean,JSONPath=`.spec.maintenanceMode`
// +kubebuilder:printcolumn:name="Phase",type=string,JSONPath=`.status.phase`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`

// Maintenance is the Schema for the maintenances API.
type Maintenance struct {
	metav1.TypeMeta `json:",inline"`

	// Standard object metadata.
	metav1.ObjectMeta `json:"metadata,omitempty"`

	// Desired state.
	Spec MaintenanceSpec `json:"spec"`

	// Observed state.
	// +optional
	Status MaintenanceStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// MaintenanceList contains a list of Maintenance.
type MaintenanceList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`

	Items []Maintenance `json:"items"`
}

func init() {
	SchemeBuilder.Register(func(s *runtime.Scheme) error {
		s.AddKnownTypes(
			SchemeGroupVersion,
			&Maintenance{},
			&MaintenanceList{},
		)
		return nil
	})
}
