//! Comprehensive unit tests for VDF engine
//!
//! Tests cover all VDF backends, beacon generation/verification,
//! error conditions, edge cases, and mathematical properties.

// Removed duplicated #![cfg(test)] per clippy suggestion; tests.rs is only compiled in test profile via lib.rs cfg(test)
#![allow(clippy::missing_panics_doc)]

use super::*;
use alloc::vec;
use alloc::vec::Vec;
use alloc::format;

/// Test helper to generate deterministic test data
fn test_hash(input: &str) -> Hash256 {
    h_tag("test.data", &[input.as_bytes()])
}

/// Test helper to generate test parent header ID
fn test_parent_id() -> Hash256 {
    test_hash("test_parent_header")
}

#[test]
fn test_le_bytes_encoding() {
    // Test little-endian encoding with different widths
    assert_eq!(le_bytes::<1>(0x42), [0x42]);
    assert_eq!(le_bytes::<2>(0x1234), [0x34, 0x12]);
    assert_eq!(le_bytes::<4>(0x1234_5678), [0x78, 0x56, 0x34, 0x12]);
    assert_eq!(le_bytes::<8>(0x1234_5678_9ABC_DEF0), [0xF0, 0xDE, 0xBC, 0x9A, 0x78, 0x56, 0x34, 0x12]);
    
    // Test overflow handling
    assert_eq!(le_bytes::<2>(0x0012_3456), [0x56, 0x34]); // Truncated
}

#[test]
fn test_h_tag_domain_separation() {
    let data1 = b"test_data";
    let data2 = b"other_data";
    
    // Same tag, same data should produce same hash
    let hash_first = h_tag("test.tag", &[data1]);
    let hash_second = h_tag("test.tag", &[data1]);
    assert_eq!(hash_first, hash_second);
    
    // Different tags should produce different hashes
    let hash2 = h_tag("other.tag", &[data1]);
    assert_ne!(hash_first, hash2);
    
    // Different data should produce different hashes
    let hash3 = h_tag("test.tag", &[data2]);
    assert_ne!(hash_first, hash3);
    
    // Multiple parts should be handled correctly
    let hash4 = h_tag("test.tag", &[data1, data2]);
    let mut combined = Vec::new();
    combined.extend_from_slice(data1);
    combined.extend_from_slice(data2);
    let hash5 = h_tag("test.tag", &[&combined]);
    assert_ne!(hash4, hash5); // Length framing should prevent collision
}

#[test]
fn test_slot_seed_deterministic() {
    let parent_id = test_parent_id();
    let slot1 = 100;
    let slot2 = 101;
    
    // Same inputs should produce same seed
    let seed_first = slot_seed(&parent_id, slot1);
    let seed_second = slot_seed(&parent_id, slot1);
    assert_eq!(seed_first, seed_second);
    
    // Different slots should produce different seeds
    let seed2 = slot_seed(&parent_id, slot2);
    assert_ne!(seed_first, seed2);
    
    // Different parent IDs should produce different seeds
    let other_parent = test_hash("other_parent");
    let seed3 = slot_seed(&other_parent, slot1);
    assert_ne!(seed_first, seed3);
}

#[test]
fn test_canonical_helpers() {
    let test_data = b"test_y_raw_data";
    
    // ycore_from_raw should be deterministic
    let ycore1 = ycore_from_raw(test_data);
    let ycore2 = ycore_from_raw(test_data);
    assert_eq!(ycore1, ycore2);
    
    // Different data should produce different ycore
    let ycore3 = ycore_from_raw(b"different_data");
    assert_ne!(ycore1, ycore3);
    
    // yedge_from_ycore should be deterministic
    let yedge1 = yedge_from_ycore(&ycore1);
    let yedge2 = yedge_from_ycore(&ycore1);
    assert_eq!(yedge1, yedge2);
    
    // Different ycore should produce different yedge
    let yedge3 = yedge_from_ycore(&ycore3);
    assert_ne!(yedge1, yedge3);
}

#[test]
fn test_beacon_structure() {
    let seed = test_hash("test_seed");
    let ycore = test_hash("test_ycore");
    let yedge = test_hash("test_yedge");
    let pi = vec![1, 2, 3, 4];
    let ell = vec![5, 6, 7, 8];
    
    let beacon = Beacon {
        seed_commit: seed,
        vdf_y_core: ycore,
        vdf_y_edge: yedge,
        vdf_pi: pi.clone(),
        vdf_ell: ell.clone(),
    };
    
    assert_eq!(beacon.seed_commit, seed);
    assert_eq!(beacon.vdf_y_core, ycore);
    assert_eq!(beacon.vdf_y_edge, yedge);
    assert_eq!(beacon.vdf_pi, pi);
    assert_eq!(beacon.vdf_ell, ell);
}

#[cfg(feature = "mock-backend")]
mod mock_backend_tests {
    use super::*;
    use crate::mock_backend::MockVdfBackend;
    
    #[test]
    fn test_mock_vdf_deterministic() {
        let seed = test_hash("mock_test_seed");
        let delay = 10;
        
        // Multiple evaluations should produce same result
        let (y1, pi1, ell1) = MockVdfBackend::eval(&seed, delay);
        let (y2, pi2, ell2) = MockVdfBackend::eval(&seed, delay);
        
        assert_eq!(y1, y2);
        assert_eq!(pi1, pi2);
        assert_eq!(ell1, ell2);
        
        // Different seeds should produce different results
        let other_seed = test_hash("other_mock_seed");
        let (y3, pi3, _) = MockVdfBackend::eval(&other_seed, delay);
        assert_ne!(y1, y3);
        assert_ne!(pi1, pi3);
        
        // Different delays should produce different results
        let (y4, pi4, _) = MockVdfBackend::eval(&seed, delay + 1);
        assert_ne!(y1, y4);
        assert_ne!(pi1, pi4);
    }
    
    #[test]
    fn test_mock_vdf_verification() {
        let seed = test_hash("mock_verify_seed");
        let delay = 15;
        
        let (y_raw, pi, ell) = MockVdfBackend::eval(&seed, delay);
        
        // Valid proof should verify
        let (valid, returned_y) = MockVdfBackend::verify(&seed, delay, &pi, &ell);
        assert!(valid);
        assert_eq!(returned_y, y_raw);
        
        // Invalid proof should not verify
        let mut invalid_pi = pi.clone();
        invalid_pi[0] ^= 1; // Flip one bit
        let (valid, returned_y) = MockVdfBackend::verify(&seed, delay, &invalid_pi, &ell);
        assert!(!valid);
        assert_eq!(returned_y, y_raw); // Mock backend always returns expected y_raw
        
        // Wrong delay should not verify
        let (valid, returned_y) = MockVdfBackend::verify(&seed, delay + 1, &pi, &ell);
        assert!(!valid);
        assert!(!returned_y.is_empty()); // Returns y_raw for the wrong delay
        
        // Wrong seed should not verify
        let other_seed = test_hash("wrong_seed");
        let (valid, returned_y) = MockVdfBackend::verify(&other_seed, delay, &pi, &ell);
        assert!(!valid);
        assert!(!returned_y.is_empty()); // Returns y_raw for the wrong seed
    }
    
    #[test]
    fn test_mock_build_beacon() {
        let parent_id = test_parent_id();
        let slot = 42;
        
        let result = build_beacon::<MockVdfBackend>(&parent_id, slot);
        assert!(result.is_ok());
        
        let beacon = result.unwrap();
        
        // Verify seed commitment
        let expected_seed = slot_seed(&parent_id, slot);
        assert_eq!(beacon.seed_commit, expected_seed);
        
        // Verify ycore and yedge derivation
        // For mock backend, we need to recompute y_raw to verify y_core
        let (y_raw, _, _) = MockVdfBackend::eval(&expected_seed, constants::VDF_DELAY_T);
        let expected_ycore = ycore_from_raw(&y_raw);
        assert_eq!(beacon.vdf_y_core, expected_ycore);
        
        let expected_yedge = yedge_from_ycore(&beacon.vdf_y_core);
        assert_eq!(beacon.vdf_y_edge, expected_yedge);
        
        // Verify proof sizes are reasonable
        assert!(!beacon.vdf_pi.is_empty());
        assert!(beacon.vdf_pi.len() <= constants::MAX_PI_LEN);
        assert!(beacon.vdf_ell.len() <= constants::MAX_ELL_LEN);
    }
    
    #[test]
    fn test_mock_verify_beacon() {
        let parent_id = test_parent_id();
        let slot = 123;
        
        // Build a valid beacon
        let beacon = build_beacon::<MockVdfBackend>(&parent_id, slot).unwrap();
        
        // Verification should succeed
        let result = verify_beacon::<MockVdfBackend>(&parent_id, slot, &beacon);
        assert!(result.is_ok());
        
        // Wrong parent ID should fail
        let wrong_parent = test_hash("wrong_parent");
        let result = verify_beacon::<MockVdfBackend>(&wrong_parent, slot, &beacon);
        assert!(matches!(result, Err(VerifyErr::SeedMismatch)));
        
        // Wrong slot should fail
        let result = verify_beacon::<MockVdfBackend>(&parent_id, slot + 1, &beacon);
        assert!(matches!(result, Err(VerifyErr::SeedMismatch)));
        
        // Corrupted proof should fail
        let mut corrupted_beacon = beacon.clone();
        corrupted_beacon.vdf_pi[0] ^= 1;
        let result = verify_beacon::<MockVdfBackend>(&parent_id, slot, &corrupted_beacon);
        assert!(matches!(result, Err(VerifyErr::BackendInvalid)));
        
        // Corrupted ycore should fail
        let mut corrupted_beacon = beacon.clone();
        corrupted_beacon.vdf_y_core[0] ^= 1;
        let result = verify_beacon::<MockVdfBackend>(&parent_id, slot, &corrupted_beacon);
        assert!(matches!(result, Err(VerifyErr::CoreMismatch)));
        
        // Corrupted yedge should fail
        let mut corrupted_beacon = beacon;
        corrupted_beacon.vdf_y_edge[0] ^= 1;
        let result = verify_beacon::<MockVdfBackend>(&parent_id, slot, &corrupted_beacon);
        assert!(matches!(result, Err(VerifyErr::EdgeMismatch)));
    }
}

#[cfg(feature = "rsa-backend")]
mod rsa_backend_tests {
    use super::*;
    use crate::rsa_backend::RsaVdfBackend;
    
    #[test]
    fn test_rsa_vdf_deterministic() {
        let seed = test_hash("rsa_test_seed");
        let delay = 5; // Small delay for testing
        
        // Multiple evaluations should produce same result
        let (y1, pi1, ell1) = RsaVdfBackend::eval(&seed, delay);
        let (y2, pi2, ell2) = RsaVdfBackend::eval(&seed, delay);
        
        assert_eq!(y1, y2);
        assert_eq!(pi1, pi2);
        assert_eq!(ell1, ell2);
        
        // Different seeds should produce different results
        let other_seed = test_hash("other_rsa_seed");
        let (y3, pi3, _) = RsaVdfBackend::eval(&other_seed, delay);
        assert_ne!(y1, y3);
        assert_ne!(pi1, pi3);
    }
    
    #[test]
    fn test_rsa_vdf_verification() {
        let seed = test_hash("rsa_verify_seed");
        let delay = 3; // Small delay for testing
        
        let (y_raw, pi, ell) = RsaVdfBackend::eval(&seed, delay);
        
        // Valid proof should verify
        let (valid, returned_y) = RsaVdfBackend::verify(&seed, delay, &pi, &ell);
        assert!(valid);
        assert_eq!(returned_y, y_raw);
        
        // Invalid proof should not verify
        let mut invalid_pi = pi;
        if !invalid_pi.is_empty() {
            invalid_pi[0] ^= 1; // Flip one bit
            let (valid, returned_y) = RsaVdfBackend::verify(&seed, delay, &invalid_pi, &ell);
            assert!(!valid);
            assert!(returned_y.is_empty());
        }
    }
    
    #[test]
    fn test_rsa_build_verify_beacon() {
        let parent_id = test_parent_id();
        let slot = 456;
        
        // Build beacon
        let beacon = build_beacon::<RsaVdfBackend>(&parent_id, slot).unwrap();
        
        // Verify beacon
        let result = verify_beacon::<RsaVdfBackend>(&parent_id, slot, &beacon);
        assert!(result.is_ok());
        
        // Verify proof sizes are within limits
        assert!(beacon.vdf_pi.len() <= constants::MAX_PI_LEN);
        assert!(beacon.vdf_ell.len() <= constants::MAX_ELL_LEN);
    }
}

#[cfg(feature = "class-group-backend")]
mod classgroup_backend_tests {
    use super::*;
    use crate::classgroup_backend::{ClassGroupVdfBackend, BinaryQuadraticForm};
    use num_bigint::BigInt;
    
    #[test]
    fn test_binary_quadratic_form() {
        let a = BigInt::from(2);
        let b = BigInt::from(1);
        let c = BigInt::from(3);
        
        let form = BinaryQuadraticForm::new(a.clone(), b.clone(), c.clone());
        
        // Test discriminant calculation
        let discriminant = form.discriminant();
        let expected = &b * &b - 4 * &a * &c; // 1 - 24 = -23
        assert_eq!(discriminant, expected);
        
        // Test serialization/deserialization
        let bytes = form.to_bytes();
        let deserialized = BinaryQuadraticForm::from_bytes(&bytes).unwrap();
        assert_eq!(form, deserialized);
    }
    
    #[test]
    fn test_form_operations() {
        let form1 = BinaryQuadraticForm::new(BigInt::from(1), BigInt::from(0), BigInt::from(1));
        let form2 = BinaryQuadraticForm::new(BigInt::from(2), BigInt::from(1), BigInt::from(1));
        
        // Test squaring
        let squared = form1.square();
        assert!(squared.discriminant() == form1.discriminant());
        
        // Test composition
        let composed = form1.compose(&form2);
        assert!(composed.discriminant() == form1.discriminant());
        
        // Test power of two
        let power = form1.power_of_two(3);
        let manual = form1.square().square().square();
        assert_eq!(power, manual);
    }
    
    #[test]
    fn test_classgroup_vdf_deterministic() {
        let seed = test_hash("classgroup_test_seed");
        let delay = 4; // Small delay for testing
        
        // Multiple evaluations should produce same result
        let (y1, pi1, ell1) = ClassGroupVdfBackend::eval(&seed, delay);
        let (y2, pi2, ell2) = ClassGroupVdfBackend::eval(&seed, delay);
        
        assert_eq!(y1, y2);
        assert_eq!(pi1, pi2);
        assert_eq!(ell1, ell2);
        
        // Different seeds should produce different results
        let other_seed = test_hash("other_classgroup_seed");
        let (y3, pi3, _) = ClassGroupVdfBackend::eval(&other_seed, delay);
        assert_ne!(y1, y3);
        assert_ne!(pi1, pi3);
    }
    
    #[test]
    fn test_classgroup_vdf_verification() {
        let seed = test_hash("classgroup_verify_seed");
        let delay = 2; // Small delay for testing
        
        let (y_raw, pi, ell) = ClassGroupVdfBackend::eval(&seed, delay);
        
        // Valid proof should verify
        let (valid, returned_y) = ClassGroupVdfBackend::verify(&seed, delay, &pi, &ell);
        assert!(valid);
        assert_eq!(returned_y, y_raw);
        
        // Invalid proof should not verify
        let mut invalid_pi = pi;
        if !invalid_pi.is_empty() {
            invalid_pi[0] ^= 1; // Flip one bit
            let (valid, returned_y) = ClassGroupVdfBackend::verify(&seed, delay, &invalid_pi, &ell);
            assert!(!valid);
            assert!(returned_y.is_empty());
        }
    }
    
    #[test]
    fn test_classgroup_build_verify_beacon() {
        let parent_id = test_parent_id();
        let slot = 789;
        
        // Build beacon
        let beacon = build_beacon::<ClassGroupVdfBackend>(&parent_id, slot).unwrap();
        
        // Verify beacon
        let result = verify_beacon::<ClassGroupVdfBackend>(&parent_id, slot, &beacon);
        assert!(result.is_ok());
        
        // Verify proof sizes are within limits
        assert!(beacon.vdf_pi.len() <= constants::MAX_PI_LEN);
        assert!(beacon.vdf_ell.len() <= constants::MAX_ELL_LEN);
    }
}

#[test]
fn test_proof_size_limits() {
    // Test that oversized proofs are rejected
    let parent_id = test_parent_id();
    let slot = 999;
    let seed = slot_seed(&parent_id, slot);
    
    // Create oversized proof
    let oversized_pi = vec![0u8; constants::MAX_PI_LEN + 1];
    let oversized_ell = vec![0u8; constants::MAX_ELL_LEN + 1];
    
    let beacon_oversized_pi = Beacon {
        seed_commit: seed,
        vdf_y_core: test_hash("ycore"),
        vdf_y_edge: test_hash("yedge"),
        vdf_pi: oversized_pi,
        vdf_ell: vec![],
    };
    
    let beacon_oversized_ell = Beacon {
        seed_commit: seed,
        vdf_y_core: test_hash("ycore"),
        vdf_y_edge: test_hash("yedge"),
        vdf_pi: vec![],
        vdf_ell: oversized_ell,
    };
    
    // Verification should reject oversized proofs
    #[cfg(feature = "mock-backend")]
    {
        use crate::mock_backend::MockVdfBackend;
        
        let result = verify_beacon::<MockVdfBackend>(&parent_id, slot, &beacon_oversized_pi);
        assert!(matches!(result, Err(VerifyErr::ProofTooLarge)));
        
        let result = verify_beacon::<MockVdfBackend>(&parent_id, slot, &beacon_oversized_ell);
        assert!(matches!(result, Err(VerifyErr::ProofTooLarge)));
    }
}

#[test]
fn test_constants_validity() {
    // Note: Constants are validated at compile time
    // Clippy warns about assertions on constants as they are optimized out
    // These constants are verified through type system and compilation
    
    // Verify timing relationships where meaningful
    // Using runtime computation to avoid const assertion warnings
    let slot_ms = constants::SLOT_MS;
    let eval_budget_ms = constants::EVAL_BUDGET_MS;
    let vdf_delay_t = constants::VDF_DELAY_T;
    
    assert!(eval_budget_ms < slot_ms);
    assert!(vdf_delay_t < eval_budget_ms);
}

#[test]
fn test_error_types() {
    // Test that error types can be created and formatted
    let build_err = BuildErr::ProofTooLarge;
    assert!(!format!("{build_err:?}").is_empty());
    
    let verify_errors = [
        VerifyErr::SeedMismatch,
        VerifyErr::ProofTooLarge,
        VerifyErr::BackendInvalid,
        VerifyErr::CoreMismatch,
        VerifyErr::EdgeMismatch,
    ];
    
    for err in &verify_errors {
        assert!(!format!("{err:?}").is_empty());
    }
}

#[test]
fn test_edge_cases() {
    // Test with zero delay (should still work)
    #[cfg(feature = "mock-backend")]
    {
        use crate::mock_backend::MockVdfBackend;
        
        let seed = test_hash("zero_delay_test");
        let (y_raw, pi, ell) = MockVdfBackend::eval(&seed, 0);
        let (valid, returned_y) = MockVdfBackend::verify(&seed, 0, &pi, &ell);
        assert!(valid);
        assert_eq!(returned_y, y_raw);
    }
    
    // Test with maximum reasonable delay
    #[cfg(feature = "mock-backend")]
    {
        use crate::mock_backend::MockVdfBackend;
        
        let seed = test_hash("max_delay_test");
        let max_delay = 100; // Reasonable maximum for testing
        let (y_raw, pi, ell) = MockVdfBackend::eval(&seed, max_delay);
        let (valid, returned_y) = MockVdfBackend::verify(&seed, max_delay, &pi, &ell);
        assert!(valid);
        assert_eq!(returned_y, y_raw);
    }
    
    // Test with empty proof data
    #[cfg(feature = "mock-backend")]
    {
        use crate::mock_backend::MockVdfBackend;
        
        let seed = test_hash("empty_proof_test");
        let (valid, returned_y) = MockVdfBackend::verify(&seed, 10, &[], &[]);
        assert!(!valid);
        assert!(!returned_y.is_empty()); // Mock backend returns expected y_raw even for empty proof
    }
}

#[test]
fn test_mathematical_properties() {
    // Test that VDF outputs have expected entropy
    #[cfg(feature = "mock-backend")]
    {
        use crate::mock_backend::MockVdfBackend;
        
        let mut outputs = Vec::new();
        for i in 0..10 {
            let seed = test_hash(&format!("entropy_test_{i}"));
            let (y_raw, _, _) = MockVdfBackend::eval(&seed, 10);
            outputs.push(y_raw);
        }
        
        // All outputs should be different (high probability)
        for i in 0..outputs.len() {
            for j in i + 1..outputs.len() {
                assert_ne!(outputs[i], outputs[j]);
            }
        }
    }
    
    // Test that verification is consistent
    #[cfg(feature = "mock-backend")]
    {
        use crate::mock_backend::MockVdfBackend;
        
        let seed = test_hash("consistency_test");
        let delay = 15;
        let (y_raw, pi, ell) = MockVdfBackend::eval(&seed, delay);
        
        // Multiple verifications should give same result
        for _ in 0..5 {
            let (valid, returned_y) = MockVdfBackend::verify(&seed, delay, &pi, &ell);
            assert!(valid);
            assert_eq!(returned_y, y_raw);
        }
    }
}

#[test]
fn test_beacon_integration() {
    // Test full beacon workflow with different backends
    let parent_id = test_parent_id();
    let slot = 12345;
    
    #[cfg(feature = "mock-backend")]
    {
        use crate::mock_backend::MockVdfBackend;
        
        // Build and verify beacon
        let beacon = build_beacon::<MockVdfBackend>(&parent_id, slot).unwrap();
        let result = verify_beacon::<MockVdfBackend>(&parent_id, slot, &beacon);
        assert!(result.is_ok());
        
        // Test beacon properties
        assert_eq!(beacon.seed_commit, slot_seed(&parent_id, slot));
        // For mock backend, recompute y_raw to verify y_core
        let (y_raw, _, _) = MockVdfBackend::eval(&beacon.seed_commit, constants::VDF_DELAY_T);
        assert_eq!(beacon.vdf_y_core, ycore_from_raw(&y_raw));
        assert_eq!(beacon.vdf_y_edge, yedge_from_ycore(&beacon.vdf_y_core));
    }
    
    #[cfg(feature = "rsa-backend")]
    {
        use crate::rsa_backend::RsaVdfBackend;
        
        let beacon = build_beacon::<RsaVdfBackend>(&parent_id, slot).unwrap();
        let result = verify_beacon::<RsaVdfBackend>(&parent_id, slot, &beacon);
        assert!(result.is_ok());
    }
    
    #[cfg(feature = "class-group-backend")]
    {
        use crate::classgroup_backend::ClassGroupVdfBackend;
        
        let beacon = build_beacon::<ClassGroupVdfBackend>(&parent_id, slot).unwrap();
        let result = verify_beacon::<ClassGroupVdfBackend>(&parent_id, slot, &beacon);
        assert!(result.is_ok());
    }
}
