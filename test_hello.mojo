from std.testing import assert_equal, assert_true, assert_false

def add(a: Int, b: Int) -> Int:
    return a + b

def greet(name: String) -> String:
    return "Hello, " + name + "!"

def main() raises:
    # 測試 add 函數
    assert_equal(add(1, 2), 3, msg="1 + 2 應等於 3")
    assert_equal(add(0, 0), 0, msg="0 + 0 應等於 0")
    assert_equal(add(-1, 1), 0, msg="-1 + 1 應等於 0")

    # 測試 greet 函數
    assert_equal(greet("World"), "Hello, World!", msg="greet('World') 結果錯誤")
    assert_equal(greet("Mojo"), "Hello, Mojo!", msg="greet('Mojo') 結果錯誤")

    # 測試布林斷言
    assert_true(add(2, 3) > 0, msg="2+3 應大於 0")
    assert_false(add(1, 1) == 3, msg="1+1 不應等於 3")

    print("所有測試通過！")
