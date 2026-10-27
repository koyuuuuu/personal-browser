// Build-time adapter for Brave's MPL-2.0 adblock-rust. No Rust code is linked into the iOS app.
use adblock::lists::{FilterSet, ParseOptions};
use std::{env, fs, io::{self, Write}};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut filters = FilterSet::new(true);
    let mut lines = 0;
    for file in env::args().skip(1) {
        let text = fs::read_to_string(file)?;
        lines += text.lines().filter(|s| !s.is_empty() && !s.starts_with('!') && !s.starts_with('[')).count();
        filters.add_filter_list(text, ParseOptions::default());
    }
    let (rules, used) = filters.into_content_blocking().map_err(|_| "Filter conversion failed")?;
    let output = serde_json::json!({"rules": rules, "inputLines": lines, "convertedFilters": used.len()});
    serde_json::to_writer(io::stdout().lock(), &output)?;
    io::stdout().flush()?;
    Ok(())
}
