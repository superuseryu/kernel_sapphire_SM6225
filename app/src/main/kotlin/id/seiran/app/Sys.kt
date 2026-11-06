package id.seiran.app

import com.topjohnwu.superuser.Shell
import java.io.FileInputStream

data class Stats(
    val zramAlgo: String?,
    val zramRecomp: String?,
    val zramMb: Long?,
    val io: String?,
    val cpuidle: String?,
    val gov0: String?,
    val gov4: String?,
    val batFull: Long?,
    val batDesign: Long?,
    val ufsA: String?,
    val ufsB: String?,
    val memSleep: String?,
) {
    val health: String?
        get() {
            val f = batFull
            val d = batDesign
            if (f == null || d == null || d <= 0L) return null
            val t = f * 1000 / d
            return "${t / 10}.${t % 10}%"
        }

    val battery: String?
        get() {
            val f = batFull
            val d = batDesign
            if (f == null || d == null) return null
            return "${f / 1000}/${d / 1000} mAh"
        }
}

object Sys {
    fun read(path: String, root: Boolean): String? {
        try {
            val t = FileInputStream(path).bufferedReader().use { it.readText() }.trim()
            if (t.isNotEmpty()) return t
        } catch (_: Exception) {
        }
        if (root) {
            val r = Shell.cmd("cat $path").exec()
            if (r.isSuccess) {
                return r.out.joinToString("\n").trim().ifEmpty { null }
            }
        }
        return null
    }

    // "[lz4] zstd" -> "lz4", "#1: lz4 [zstd]" -> "zstd"
    fun active(s: String?): String? =
        s?.let { Regex("\\[([^\\]]+)]").find(it)?.groupValues?.get(1) }

    fun grantRoot(): Boolean = try {
        Shell.getShell().isRoot
    } catch (_: Throwable) {
        false
    }

    fun load(root: Boolean): Stats {
        fun r(p: String) = read(p, root)
        val ufs = "/sys/devices/platform/soc/4804000.ufshc/health_descriptor"
        return Stats(
            zramAlgo = active(r("/sys/block/zram0/comp_algorithm")),
            zramRecomp = active(r("/sys/block/zram0/recomp_algorithm")),
            zramMb = r("/sys/block/zram0/disksize")?.toLongOrNull()?.div(1048576L),
            io = listOf("sda", "sdb", "sdc", "sdd").firstNotNullOfOrNull {
                active(r("/sys/block/$it/queue/scheduler"))
            },
            cpuidle = r("/sys/devices/system/cpu/cpuidle/current_governor"),
            gov0 = r("/sys/devices/system/cpu/cpufreq/policy0/scaling_governor"),
            gov4 = r("/sys/devices/system/cpu/cpufreq/policy4/scaling_governor"),
            batFull = r("/sys/class/power_supply/battery/charge_full")?.toLongOrNull(),
            batDesign = r("/sys/class/power_supply/battery/charge_full_design")?.toLongOrNull(),
            ufsA = r("$ufs/life_time_estimation_a"),
            ufsB = r("$ufs/life_time_estimation_b"),
            memSleep = active(r("/sys/power/mem_sleep")),
        )
    }
}
