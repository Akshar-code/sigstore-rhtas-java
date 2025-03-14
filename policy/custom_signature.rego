package ec

#fail if there is NOT a signature from akottuva@redhat.com
violation[msg] {
  not some att in input.attestations {
    att.subject == "akottuva@redhat.com"
  }
  msg := "No signature found from akottuva@redhat.com"
}
